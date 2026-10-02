#!/usr/bin/env python3
"""Export x.com / twitter.com session cookies from YOUR local browser profile.

Run this yourself on the machine where you are already signed in to X. It reads
only auth_token and ct0 for x.com / twitter.com from a Chromium-family or
Firefox cookie store and writes:

    ~/.config/ande.launcher/x-cookies.json

That file is for the X tile only. Never commit it, never paste tokens into chat
or the repo, and delete it if you no longer want the widget signed in.

Consent: by continuing you confirm this is your browser profile on this account
and you want the launcher to use those cookies locally. Close the target browser
first if the Cookies database is locked.

Linux: Chromium / Google Chrome / Brave (secretstorage or keyring or secret-tool
for the Safe Storage password; falls back to the legacy "peanuts" key).
macOS: same browsers via Keychain ("… Safe Storage"); Firefox profiles under
~/Library/Application Support/Firefox.
Firefox (Linux + macOS): cookies.sqlite (plaintext values).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

COOKIE_NAMES = ("auth_token", "ct0")
HOST_SUFFIXES = ("x.com", "twitter.com")
DEFAULT_OUT = Path(
    os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
) / "ande.launcher" / "x-cookies.json"

# Chromium Safe Storage labels / account names by browser id.
CHROMIUM_BROWSERS = {
    "chrome": {
        "label": "Chrome Safe Storage",
        "linux_paths": (
            Path.home() / ".config" / "google-chrome",
            Path.home() / ".config" / "google-chrome-beta",
            Path.home() / ".config" / "google-chrome-unstable",
        ),
        "mac_paths": (
            Path.home() / "Library" / "Application Support" / "Google" / "Chrome",
        ),
    },
    "chromium": {
        "label": "Chromium Safe Storage",
        "linux_paths": (Path.home() / ".config" / "chromium",),
        "mac_paths": (
            Path.home() / "Library" / "Application Support" / "Chromium",
        ),
    },
    "brave": {
        "label": "Brave Safe Storage",
        "linux_paths": (
            Path.home() / ".config" / "BraveSoftware" / "Brave-Browser",
        ),
        "mac_paths": (
            Path.home() / "Library" / "Application Support" / "BraveSoftware" / "Brave-Browser",
        ),
    },
}


def eprint(*args):
    print(*args, file=sys.stderr)


def platform_name():
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "darwin"
    return sys.platform


def host_matches(host):
    host = (host or "").lstrip(".").lower()
    return any(host == suffix or host.endswith("." + suffix) for suffix in HOST_SUFFIXES)


def confirm_consent(assume_yes):
    eprint("This helper will:")
    eprint("  • read YOUR local browser cookies for x.com / twitter.com only")
    eprint("  • extract auth_token and ct0 (session secrets)")
    eprint("  • write them to", str(DEFAULT_OUT), "(mode 0600)")
    eprint("  • never upload anything; never commit that file")
    eprint("")
    eprint("Close the browser first if export fails with a database lock.")
    if assume_yes:
        return True
    if not sys.stdin.isatty():
        eprint("Non-interactive stdin: pass --yes to confirm.")
        return False
    answer = input("Continue? [y/N] ").strip().lower()
    return answer in ("y", "yes")


def pbkdf2_key(password: bytes, iterations: int) -> bytes:
    return hashlib.pbkdf2_hmac("sha1", password, b"saltysalt", iterations, dklen=16)


def openssl_aes128_cbc_decrypt(ciphertext: bytes, key: bytes) -> bytes:
    iv = b" " * 16
    proc = subprocess.run(
        [
            "openssl",
            "enc",
            "-aes-128-cbc",
            "-d",
            "-K",
            key.hex(),
            "-iv",
            iv.hex(),
        ],
        input=ciphertext,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", "replace").strip()
        raise RuntimeError(err or "openssl decrypt failed")
    return proc.stdout


def decrypt_chromium_value(encrypted: bytes, key: bytes, db_version: int, host_key: str) -> str:
    if not encrypted:
        return ""
    if encrypted.startswith(b"v10") or encrypted.startswith(b"v11"):
        prefix_len = 3
    else:
        # Unencrypted / legacy
        try:
            return encrypted.decode("utf-8")
        except UnicodeDecodeError:
            return ""
    ciphertext = encrypted[prefix_len:]
    if not ciphertext:
        return ""
    plain = openssl_aes128_cbc_decrypt(ciphertext, key)
    if db_version >= 24 and len(plain) >= 32:
        # Chromium ≥130 prefixes SHA-256(host_key) before the value.
        expected = hashlib.sha256(host_key.encode("utf-8")).digest()
        if plain[:32] == expected:
            plain = plain[32:]
        else:
            # Some builds still omit the tag; keep bytes as-is if UTF-8 works.
            try:
                return plain.decode("utf-8")
            except UnicodeDecodeError:
                plain = plain[32:]
    return plain.decode("utf-8")


def linux_safe_storage_password(label: str) -> bytes | None:
    # 1) secretstorage
    try:
        import secretstorage  # type: ignore

        bus = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(bus)
        if collection.is_locked():
            collection.unlock()
        for item in collection.get_all_items():
            if item.get_label() == label:
                secret = item.get_secret()
                return bytes(secret) if not isinstance(secret, bytes) else secret
    except Exception as exc:
        eprint("secretstorage:", exc)

    # 2) keyring
    try:
        import keyring  # type: ignore

        value = keyring.get_password(label, label.split()[0])
        if value:
            return value.encode("utf-8")
        value = keyring.get_password("Chrome Safe Storage", "Chrome")
        if label.startswith("Chrome") and value:
            return value.encode("utf-8")
    except Exception as exc:
        eprint("keyring:", exc)

    # 3) secret-tool CLI
    for lookup in (
        ["secret-tool", "lookup", "application", "chrome"],
        ["secret-tool", "lookup", "xdg:schema", "chrome_libsecret_os_crypt_password_v2"],
    ):
        try:
            proc = subprocess.run(lookup, capture_output=True, check=False, text=True)
            if proc.returncode == 0 and proc.stdout.strip():
                return proc.stdout.strip().encode("utf-8")
        except FileNotFoundError:
            break
        except Exception:
            pass

    return None


def darwin_safe_storage_password(label: str) -> bytes | None:
    # Keychain stores the passphrase; Chromium uses the base64 string as-is.
    try:
        proc = subprocess.run(
            ["security", "find-generic-password", "-w", "-s", label],
            capture_output=True,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    except FileNotFoundError:
        eprint("macOS Keychain helper (security) not found")
    except Exception as exc:
        eprint("Keychain:", exc)
    return None


def chromium_password(browser_id: str) -> tuple[bytes, int]:
    label = CHROMIUM_BROWSERS[browser_id]["label"]
    plat = platform_name()
    if plat == "darwin":
        secret = darwin_safe_storage_password(label)
        iterations = 1003
        if secret is None:
            eprint("Keychain miss for", label, "— cookie decrypt will fail")
            secret = b"peanuts"
        return secret, iterations
    secret = linux_safe_storage_password(label)
    iterations = 1
    if secret is None:
        eprint("No Liberator/keyring secret for", label, "— trying legacy password 'peanuts'")
        secret = b"peanuts"
    return secret, iterations


def copy_sqlite(src: Path) -> Path:
    """Copy a SQLite DB (and WAL/journal siblings) so we can read while locked."""
    tmp = Path(tempfile.mkdtemp(prefix="ande-x-cookies-"))
    dest = tmp / src.name
    shutil.copy2(src, dest)
    for suffix in ("-wal", "-shm", "-journal"):
        sibling = Path(str(src) + suffix)
        if sibling.is_file():
            shutil.copy2(sibling, Path(str(dest) + suffix))
    return dest


def chromium_db_version(conn: sqlite3.Connection) -> int:
    try:
        row = conn.execute("SELECT value FROM meta WHERE key = 'version'").fetchone()
        if row:
            return int(row[0])
    except (sqlite3.Error, TypeError, ValueError):
        pass
    return 0


def read_chromium_cookies(cookies_db: Path, browser_id: str) -> dict:
    password, iterations = chromium_password(browser_id)
    key = pbkdf2_key(password, iterations)
    copied = copy_sqlite(cookies_db)
    try:
        conn = sqlite3.connect(str(copied))
        try:
            version = chromium_db_version(conn)
            placeholders = ",".join("?" for _ in COOKIE_NAMES)
            rows = conn.execute(
                "SELECT host_key, name, encrypted_value, value FROM cookies "
                "WHERE name IN (" + placeholders + ")",
                COOKIE_NAMES,
            ).fetchall()
        finally:
            conn.close()
    finally:
        shutil.rmtree(copied.parent, ignore_errors=True)

    found = {}
    for host_key, name, encrypted_value, value in rows:
        if not host_matches(host_key):
            continue
        if name not in COOKIE_NAMES:
            continue
        raw = encrypted_value if isinstance(encrypted_value, (bytes, bytearray)) else b""
        if not raw and value:
            found[name] = str(value)
            continue
        try:
            found[name] = decrypt_chromium_value(bytes(raw), key, version, str(host_key or ""))
        except Exception as exc:
            eprint("decrypt failed for", name, "on", host_key, ":", exc)
    return found


def list_firefox_profiles() -> list[Path]:
    roots = []
    plat = platform_name()
    if plat == "linux":
        roots.append(Path.home() / ".mozilla" / "firefox")
        roots.append(Path.home() / "snap" / "firefox" / "common" / ".mozilla" / "firefox")
    elif plat == "darwin":
        roots.append(Path.home() / "Library" / "Application Support" / "Firefox" / "Profiles")
        # Also ini-based root
        roots.append(Path.home() / "Library" / "Application Support" / "Firefox")
    out = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("cookies.sqlite"):
            out.append(path)
    return out


def read_firefox_cookies(cookies_db: Path) -> dict:
    copied = copy_sqlite(cookies_db)
    try:
        conn = sqlite3.connect(str(copied))
        try:
            placeholders = ",".join("?" for _ in COOKIE_NAMES)
            rows = conn.execute(
                "SELECT host, name, value FROM moz_cookies WHERE name IN (" + placeholders + ")",
                COOKIE_NAMES,
            ).fetchall()
        finally:
            conn.close()
    finally:
        shutil.rmtree(copied.parent, ignore_errors=True)

    found = {}
    for host, name, value in rows:
        if not host_matches(host):
            continue
        if name in COOKIE_NAMES and value:
            found[name] = str(value)
    return found


def discover_chromium_cookie_dbs(browser_id: str) -> list[Path]:
    meta = CHROMIUM_BROWSERS[browser_id]
    plat = platform_name()
    roots = meta["mac_paths"] if plat == "darwin" else meta["linux_paths"]
    found = []
    for root in roots:
        if not root.is_dir():
            continue
        # Default + Profile N
        for cookies in root.glob("*/Cookies"):
            if cookies.is_file():
                found.append(cookies)
        for cookies in root.glob("Profiles/*/Cookies"):
            if cookies.is_file():
                found.append(cookies)
    return found


def pick_chromium(browser_id: str, profile: str | None) -> Path:
    if profile:
        path = Path(profile).expanduser()
        if path.is_dir():
            candidate = path / "Cookies"
            if candidate.is_file():
                return candidate
            raise SystemExit("No Cookies DB in profile dir: " + str(path))
        if path.is_file():
            return path
        raise SystemExit("Profile path not found: " + str(path))
    dbs = discover_chromium_cookie_dbs(browser_id)
    if not dbs:
        raise SystemExit(
            "No {0} cookie database found. Sign in to X in {0}, or pass --profile.".format(
                browser_id
            )
        )
    # Prefer Default
    for db in dbs:
        if db.parent.name == "Default":
            return db
    return dbs[0]


def pick_firefox(profile: str | None) -> Path:
    if profile:
        path = Path(profile).expanduser()
        if path.is_dir():
            candidate = path / "cookies.sqlite"
            if candidate.is_file():
                return candidate
            raise SystemExit("No cookies.sqlite in profile dir: " + str(path))
        if path.is_file():
            return path
        raise SystemExit("Profile path not found: " + str(path))
    dbs = list_firefox_profiles()
    if not dbs:
        raise SystemExit("No Firefox cookies.sqlite found. Pass --profile.")
    # Prefer default-release
    for db in dbs:
        parent = db.parent.name.lower()
        if "default-release" in parent or parent.endswith(".default"):
            return db
    return dbs[0]


def write_output(path: Path, cookies: dict) -> None:
    auth = str(cookies.get("auth_token") or "").strip()
    ct0 = str(cookies.get("ct0") or "").strip()
    if not auth or not ct0:
        raise SystemExit(
            "Could not find both auth_token and ct0 for x.com/twitter.com. "
            "Sign in to X in that browser, then re-run."
        )
    path = path.expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"auth_token": auth, "ct0": ct0}
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    eprint("Wrote", path)
    eprint("Keep this file private. Point the X tile cookies path at it (default).")


def auto_browser_order():
    # Prefer whatever has a Cookies DB on disk.
    order = []
    for browser_id in ("chrome", "chromium", "brave"):
        if discover_chromium_cookie_dbs(browser_id):
            order.append(("chromium", browser_id))
    if list_firefox_profiles():
        order.append(("firefox", "firefox"))
    return order


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Export x.com session cookies from a local browser into "
        "~/.config/ande.launcher/x-cookies.json for the X launcher tile."
    )
    parser.add_argument(
        "--browser",
        choices=("auto", "chrome", "chromium", "brave", "firefox"),
        default="auto",
        help="Which browser profile to read (default: auto-detect)",
    )
    parser.add_argument(
        "--profile",
        default="",
        help="Browser profile directory, or path to Cookies / cookies.sqlite",
    )
    parser.add_argument(
        "--output",
        "-o",
        default=str(DEFAULT_OUT),
        help="Output JSON path (default: %(default)s)",
    )
    parser.add_argument(
        "--yes",
        "-y",
        action="store_true",
        help="Skip the interactive consent prompt",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List discovered cookie databases and exit",
    )
    args = parser.parse_args(argv)

    if platform_name() not in ("linux", "darwin"):
        eprint("Unsupported platform:", platform_name())
        eprint("This helper targets Linux (primary) and macOS.")
        return 2

    if args.list:
        for browser_id in ("chrome", "chromium", "brave"):
            for db in discover_chromium_cookie_dbs(browser_id):
                print(browser_id, db)
        for db in list_firefox_profiles():
            print("firefox", db)
        return 0

    if not confirm_consent(args.yes):
        eprint("Aborted.")
        return 1

    profile = args.profile.strip() or None
    browser = args.browser

    if browser == "auto":
        if profile:
            # Infer from path name
            lower = str(Path(profile).expanduser()).lower()
            if "brave" in lower:
                browser = "brave"
            elif "chromium" in lower:
                browser = "chromium"
            elif "chrome" in lower:
                browser = "chrome"
            elif "firefox" in lower or str(profile).endswith("cookies.sqlite"):
                browser = "firefox"
            else:
                browser = "chrome"
        else:
            order = auto_browser_order()
            if not order:
                raise SystemExit(
                    "No Chrome/Chromium/Brave/Firefox cookie DB found under the usual paths."
                )
            kind, browser = order[0]
            eprint("Auto-selected:", browser)

    if browser == "firefox":
        db = pick_firefox(profile)
        eprint("Reading Firefox cookies from", db)
        cookies = read_firefox_cookies(db)
    else:
        db = pick_chromium(browser, profile)
        eprint("Reading", browser, "cookies from", db)
        cookies = read_chromium_cookies(db, browser)

    write_output(Path(args.output), cookies)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        eprint("Interrupted.")
        raise SystemExit(130)
