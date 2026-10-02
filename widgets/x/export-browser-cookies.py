#!/usr/bin/env python3
"""Export the signed-in X session from the local default browser.

Reads only auth_token and ct0 for x.com / twitter.com and writes:

    ~/.config/ande.launcher/x-cookies.json

Omarchy's default browsers are all supported: Chromium, Chrome, Brave,
Brave Origin, Edge, Firefox, and Zen. The settings button runs this with
--quiet. Never commit the output file.
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
SECRET_SCHEMA = "chrome_libsecret_os_crypt_password_v2"
DEFAULT_OUT = Path(
    os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
) / "ande.launcher" / "x-cookies.json"

# Omarchy's setup menu, in the same order as omarchy-default-browser.
OMARCHY_ORDER = (
    "chromium",
    "chrome",
    "brave",
    "brave-origin",
    "edge",
    "firefox",
    "zen",
)

DESKTOP_IDS = {
    "chromium.desktop": "chromium",
    "google-chrome.desktop": "chrome",
    "brave-browser.desktop": "brave",
    "brave-origin.desktop": "brave-origin",
    "microsoft-edge.desktop": "edge",
    "firefox.desktop": "firefox",
    "zen.desktop": "zen",
}

# linux/mac entries are (base, relative path). base is "config" or "home".
# Linux Edge stores its Safe Storage password under Chromium's keyring name.
# Brave Origin uses Brave's Safe Storage entry (the binary's own string).
BROWSERS = {
    "chromium": {
        "name": "Chromium",
        "kind": "chromium",
        "label": "Chromium Safe Storage",
        "application": "chromium",
        "linux": (("config", "chromium"),),
        "mac": (("home", "Library/Application Support/Chromium"),),
    },
    "chrome": {
        "name": "Chrome",
        "kind": "chromium",
        "label": "Chrome Safe Storage",
        "application": "chrome",
        "linux": (
            ("config", "google-chrome"),
            ("config", "google-chrome-beta"),
            ("config", "google-chrome-unstable"),
        ),
        "mac": (("home", "Library/Application Support/Google/Chrome"),),
    },
    "brave": {
        "name": "Brave",
        "kind": "chromium",
        "label": "Brave Safe Storage",
        "application": "brave",
        "linux": (
            ("config", "BraveSoftware/Brave-Browser"),
            ("config", "BraveSoftware/Brave-Browser-Beta"),
            ("config", "BraveSoftware/Brave-Browser-Nightly"),
        ),
        "mac": (("home", "Library/Application Support/BraveSoftware/Brave-Browser"),),
    },
    "brave-origin": {
        "name": "Brave Origin",
        "kind": "chromium",
        "label": "Brave Safe Storage",
        "application": "brave",
        "linux": (("config", "BraveSoftware/Brave-Origin"),),
        "mac": (("home", "Library/Application Support/BraveSoftware/Brave-Origin"),),
    },
    "edge": {
        "name": "Edge",
        "kind": "chromium",
        "label": "Chromium Safe Storage",
        "application": "chromium",
        "mac_label": "Microsoft Edge Safe Storage",
        "mac_account": "Microsoft Edge",
        "linux_lookups": (
            ("Chromium Safe Storage", ("chromium",)),
            ("Microsoft Edge Safe Storage", ("microsoft-edge", "edge")),
        ),
        "linux": (
            ("config", "microsoft-edge"),
            ("config", "microsoft-edge-beta"),
            ("config", "microsoft-edge-dev"),
        ),
        "mac": (("home", "Library/Application Support/Microsoft Edge"),),
    },
    "firefox": {
        "name": "Firefox",
        "kind": "firefox",
        "linux": (
            ("home", ".mozilla/firefox"),
            ("config", "mozilla/firefox"),
            ("home", "snap/firefox/common/.mozilla/firefox"),
            ("home", ".var/app/org.mozilla.firefox/.mozilla/firefox"),
            ("home", ".var/app/org.mozilla.firefox/config/mozilla/firefox"),
        ),
        "mac": (("home", "Library/Application Support/Firefox"),),
    },
    "zen": {
        "name": "Zen",
        "kind": "firefox",
        "linux": (
            ("config", "zen"),
            ("home", ".zen"),
            ("home", ".var/app/app.zen_browser.zen/.zen"),
            ("home", ".var/app/app.zen_browser.zen/config/zen"),
        ),
        "mac": (("home", "Library/Application Support/zen"),),
    },
}


class ExportError(Exception):
    pass


def eprint(*args):
    print(*args, file=sys.stderr)


def platform_name():
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "darwin"
    return sys.platform


def home_dir():
    return Path.home()


def config_dir():
    raw = os.environ.get("XDG_CONFIG_HOME")
    if raw:
        return Path(raw)
    return home_dir() / ".config"


def browser_name(browser_id):
    meta = BROWSERS.get(browser_id) or {}
    return meta.get("name") or browser_id


def normalize_browser_id(value):
    raw = str(value or "").strip().lower()
    if raw in BROWSERS:
        return raw
    if raw in DESKTOP_IDS:
        return DESKTOP_IDS[raw]
    aliases = {
        "brave origin": "brave-origin",
        "brave-browser": "brave",
        "google-chrome": "chrome",
        "google chrome": "chrome",
        "microsoft-edge": "edge",
        "microsoft edge": "edge",
        "zen-browser": "zen",
    }
    return aliases.get(raw, "")


def browser_roots(browser_id, platform=None):
    meta = BROWSERS[browser_id]
    plat = platform or platform_name()
    specs = meta["mac"] if plat == "darwin" else meta["linux"]
    roots = []
    for kind, rel in specs:
        base = home_dir() if kind == "home" else config_dir()
        roots.append(base / rel)
    return tuple(roots)


def linux_lookups(browser_id):
    meta = BROWSERS[browser_id]
    custom = meta.get("linux_lookups")
    if custom:
        return tuple(custom)
    return ((meta["label"], (meta["application"],)),)


def host_matches(host):
    host = (host or "").lstrip(".").lower()
    return any(host == suffix or host.endswith("." + suffix) for suffix in HOST_SUFFIXES)


def confirm_consent(assume_yes):
    if assume_yes:
        return True
    if not sys.stdin.isatty():
        eprint("Pass --yes to import without a prompt.")
        return False
    eprint("Import the signed-in X session from your browser for this tile?")
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
        try:
            return encrypted.decode("utf-8")
        except UnicodeDecodeError:
            return ""
    ciphertext = encrypted[prefix_len:]
    if not ciphertext:
        return ""
    plain = openssl_aes128_cbc_decrypt(ciphertext, key)
    if db_version >= 24 and len(plain) >= 32:
        expected = hashlib.sha256(host_key.encode("utf-8")).digest()
        if plain[:32] == expected:
            plain = plain[32:]
        else:
            try:
                return plain.decode("utf-8")
            except UnicodeDecodeError:
                plain = plain[32:]
    return plain.decode("utf-8")


def pick_keyring_item(items, label, applications):
    """Choose a keyring row by label and application.

    Several apps share the label "Chromium Safe Storage". The application
    attribute is what distinguishes Chromium from VS Code and the rest.
    """
    labeled = [item for item in items if item.get("label") == label]
    for app in applications:
        if not app:
            continue
        for item in labeled:
            if item.get("application") == app:
                return item
    return None


def _secretstorage_items():
    try:
        import secretstorage  # type: ignore
    except ImportError:
        return None
    bus = secretstorage.dbus_init()
    collection = secretstorage.get_default_collection(bus)
    if collection.is_locked():
        collection.unlock()
    rows = []
    for item in collection.get_all_items():
        attrs = {}
        try:
            attrs = item.get_attributes() or {}
        except Exception:
            attrs = {}
        rows.append(
            {
                "label": item.get_label(),
                "application": attrs.get("application") or "",
                "item": item,
            }
        )
    return rows


def _secret_tool_password(application):
    if not application:
        return None
    try:
        proc = subprocess.run(
            [
                "secret-tool",
                "lookup",
                "xdg:schema",
                SECRET_SCHEMA,
                "application",
                application,
            ],
            capture_output=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if proc.returncode != 0 or not proc.stdout:
        return None
    return proc.stdout.rstrip(b"\r\n")


def _desktop_is_kde():
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "") + (os.environ.get("DESKTOP_SESSION") or "")
    return "KDE" in desktop.upper()


def _kwallet_password(label):
    if shutil.which("kwallet-query") is None:
        return None
    folder = label.replace(" Safe Storage", " Keys")
    try:
        proc = subprocess.run(
            [
                "kwallet-query",
                "--read-password",
                label,
                "--folder",
                folder,
                "kdewallet",
            ],
            capture_output=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if proc.returncode != 0 or not proc.stdout:
        return None
    if proc.stdout.lower().startswith(b"failed to read"):
        return None
    return proc.stdout.rstrip(b"\r\n")


def linux_safe_storage_password(label, applications):
    applications = tuple(applications)
    try:
        rows = _secretstorage_items()
    except Exception:
        rows = None
    if rows:
        chosen = pick_keyring_item(rows, label, applications)
        if chosen is not None:
            secret = chosen["item"].get_secret()
            if isinstance(secret, bytes) and secret:
                return secret
            if secret:
                return bytes(secret)
    for app in applications:
        secret = _secret_tool_password(app)
        if secret:
            return secret
    if _desktop_is_kde():
        return _kwallet_password(label)
    return None


def darwin_safe_storage_password(label, account=""):
    commands = []
    if account:
        commands.append(["security", "find-generic-password", "-w", "-s", label, "-a", account])
    commands.append(["security", "find-generic-password", "-w", "-s", label])
    for command in commands:
        try:
            proc = subprocess.run(command, capture_output=True, check=False)
        except FileNotFoundError:
            return None
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    return None


def chromium_password(browser_id: str) -> tuple[bytes, int]:
    meta = BROWSERS[browser_id]
    plat = platform_name()
    if plat == "darwin":
        secret = darwin_safe_storage_password(meta.get("mac_label") or meta["label"], meta.get("mac_account") or "")
        iterations = 1003
    else:
        secret = None
        for label, applications in linux_lookups(browser_id):
            secret = linux_safe_storage_password(label, applications)
            if secret:
                break
        iterations = 1
    if not secret:
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
    passwords = [password]
    for extra in (b"peanuts", b""):
        if extra not in passwords:
            passwords.append(extra)
    keys = [pbkdf2_key(item, iterations) for item in passwords]
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
        if name not in COOKIE_NAMES or name in found:
            continue
        raw = encrypted_value if isinstance(encrypted_value, (bytes, bytearray)) else b""
        if not raw and value:
            found[name] = str(value)
            continue
        for key in keys:
            try:
                plain = decrypt_chromium_value(bytes(raw), key, version, str(host_key or ""))
            except Exception:
                continue
            if plain:
                found[name] = plain
                break
    return found


def parse_profiles_ini(text):
    sections = []
    current = None
    install_default = ""
    for raw_line in str(text or "").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = {"section": line[1:-1], "values": {}}
            sections.append(current)
            continue
        if current is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        current["values"][key] = value
        if current["section"].startswith("Install") and key == "Default":
            install_default = value
    return sections, install_default


def _profile_db(base: Path, rel: str, relative: bool) -> Path | None:
    if not rel:
        return None
    path = Path(rel)
    full = path if path.is_absolute() or not relative else base / rel
    db = full / "cookies.sqlite"
    if db.is_file():
        return db
    return None


def firefox_cookie_dbs(browser_id: str) -> list[Path]:
    found = []
    seen = set()

    def add(path: Path | None):
        if path is None or not path.is_file():
            return
        if "zen-workspaces" in path.parts:
            return
        key = str(path)
        if key in seen:
            return
        seen.add(key)
        found.append(path)

    for root in browser_roots(browser_id):
        if not root.is_dir():
            continue
        ini = root / "profiles.ini"
        if ini.is_file():
            try:
                parsed, install_default = parse_profiles_ini(
                    ini.read_text(encoding="utf-8", errors="replace")
                )
            except OSError:
                parsed, install_default = [], ""
            add(_profile_db(ini.parent, install_default, True))
            for section in parsed:
                values = section["values"]
                if values.get("Default") != "1":
                    continue
                relative = values.get("IsRelative", "1") != "0"
                add(_profile_db(ini.parent, values.get("Path") or "", relative))
        extras = []
        for db in root.rglob("cookies.sqlite"):
            if "zen-workspaces" in db.parts:
                continue
            if db.is_file() and str(db) not in seen:
                extras.append(db)
        extras.sort(key=lambda path: (0 if "default" in path.parent.name.lower() else 1, str(path)))
        for db in extras:
            add(db)
    return found


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
        if name in COOKIE_NAMES and value and name not in found:
            found[name] = str(value)
    return found


def profile_dir_of(cookies: Path) -> Path:
    if cookies.parent.name == "Network":
        return cookies.parent.parent
    return cookies.parent


def is_chromium_profile(name: str) -> bool:
    return name == "Default" or name == "Guest Profile" or name == "System Profile" or name.startswith("Profile ")


def cookie_db_sort_key(cookies: Path):
    profile = profile_dir_of(cookies).name
    network = 0 if cookies.parent.name == "Network" else 1
    default = 0 if profile == "Default" else 1
    return (default, network, profile.lower(), str(cookies))


def discover_chromium_cookie_dbs(browser_id: str) -> list[Path]:
    found = []
    seen = set()
    for root in browser_roots(browser_id):
        if not root.is_dir():
            continue
        for pattern in ("*/Network/Cookies", "*/Cookies"):
            for cookies in root.glob(pattern):
                if not cookies.is_file():
                    continue
                profile = profile_dir_of(cookies)
                if not is_chromium_profile(profile.name):
                    continue
                if cookies.parent.name != "Network":
                    newer = cookies.parent / "Network" / "Cookies"
                    if newer.is_file():
                        continue
                key = str(cookies)
                if key in seen:
                    continue
                seen.add(key)
                found.append(cookies)
    found.sort(key=cookie_db_sort_key)
    return found


def chromium_dbs_for(browser_id: str, profile: str | None) -> list[Path]:
    if not profile:
        return discover_chromium_cookie_dbs(browser_id)
    path = Path(profile).expanduser()
    if path.is_dir():
        for candidate in (path / "Network" / "Cookies", path / "Cookies"):
            if candidate.is_file():
                return [candidate]
        raise ExportError("No Cookies database in " + str(path))
    if path.is_file():
        return [path]
    raise ExportError("Profile path not found: " + str(path))


def firefox_dbs_for(browser_id: str, profile: str | None) -> list[Path]:
    if not profile:
        return firefox_cookie_dbs(browser_id)
    path = Path(profile).expanduser()
    if path.is_dir():
        candidate = path / "cookies.sqlite"
        if candidate.is_file():
            return [candidate]
        raise ExportError("No cookies.sqlite in " + str(path))
    if path.is_file():
        return [path]
    raise ExportError("Profile path not found: " + str(path))


def browser_has_store(browser_id: str) -> bool:
    meta = BROWSERS[browser_id]
    if meta["kind"] == "firefox":
        return bool(firefox_cookie_dbs(browser_id))
    return bool(discover_chromium_cookie_dbs(browser_id))


def infer_browser_from_path(path: str) -> str:
    lower = str(path or "").lower()
    if "brave-origin" in lower or "brave origin" in lower:
        return "brave-origin"
    if "brave" in lower:
        return "brave"
    if "microsoft-edge" in lower or "/edge" in lower:
        return "edge"
    if "chromium" in lower:
        return "chromium"
    if "chrome" in lower:
        return "chrome"
    if "zen" in lower:
        return "zen"
    if "firefox" in lower or lower.endswith("cookies.sqlite"):
        return "firefox"
    return ""


def omarchy_default_browser() -> str:
    try:
        proc = subprocess.run(
            ["omarchy-default-browser"],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError):
        return ""
    if proc.returncode != 0:
        return ""
    line = (proc.stdout or "").strip().splitlines()
    if not line:
        return ""
    return normalize_browser_id(line[0])


def resolve_browser(requested: str, profile: str | None) -> str:
    choice = (requested or "auto").strip().lower()
    if choice and choice != "auto":
        found = normalize_browser_id(choice)
        if not found:
            raise ExportError("Unknown browser.")
        return found
    if profile:
        inferred = infer_browser_from_path(profile)
        if not inferred:
            raise ExportError("Pass --browser for that profile.")
        return inferred
    default = omarchy_default_browser()
    if default:
        return default
    for browser_id in OMARCHY_ORDER:
        if browser_has_store(browser_id):
            return browser_id
    raise ExportError("No browser profile found.")


def read_browser_cookies(browser_id: str, profile: str | None) -> tuple[dict, Path | None]:
    meta = BROWSERS[browser_id]
    if meta["kind"] == "firefox":
        dbs = firefox_dbs_for(browser_id, profile)
        reader = read_firefox_cookies
    else:
        dbs = chromium_dbs_for(browser_id, profile)
        reader = lambda db: read_chromium_cookies(db, browser_id)
    if not dbs:
        raise ExportError("No " + browser_name(browser_id) + " profile found.")
    last = {}
    used = None
    for db in dbs:
        found = reader(db)
        last = found
        used = db
        if str(found.get("auth_token") or "").strip() and str(found.get("ct0") or "").strip():
            return found, db
    return last, used


def write_output(path: Path, cookies: dict, announce: bool = True) -> None:
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
    if announce:
        eprint("Wrote", path)


def session_present(path: Path) -> bool:
    path = path.expanduser()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return False
    if not isinstance(data, dict):
        return False
    return bool(str(data.get("auth_token") or "").strip() and str(data.get("ct0") or "").strip())


def status_payload(ok: bool, browser_id: str = "", error: str = "", present=None) -> dict:
    payload = {"ok": bool(ok)}
    if browser_id:
        payload["browser"] = browser_id
        payload["browserName"] = browser_name(browser_id)
    if error:
        payload["error"] = error
    if present is not None:
        payload["present"] = bool(present)
    return payload


def emit_status(payload: dict, quiet: bool) -> None:
    if quiet:
        print(json.dumps(payload), flush=True)
        return
    if payload.get("ok"):
        return
    eprint(payload.get("error") or "Import failed.")


def export_session(browser_id: str, profile: str | None, output: Path, announce: bool) -> None:
    cookies, _db = read_browser_cookies(browser_id, profile)
    if not str(cookies.get("auth_token") or "").strip() or not str(cookies.get("ct0") or "").strip():
        raise ExportError(
            "No signed-in X session in "
            + browser_name(browser_id)
            + ". Open X there and try again."
        )
    write_output(output, cookies, announce=announce)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Import the signed-in X session from the default browser "
        "into ~/.config/ande.launcher/x-cookies.json."
    )
    parser.add_argument(
        "--browser",
        choices=("auto",) + OMARCHY_ORDER,
        default="auto",
        help="Browser to read. Default: Omarchy's default browser.",
    )
    parser.add_argument(
        "--profile",
        default="",
        help="Profile directory, or a Cookies / cookies.sqlite path",
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
        help="Skip the prompt",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Skip the prompt and print one JSON status line",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Print whether the output file already has a session",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List discovered cookie databases and exit",
    )
    args = parser.parse_args(argv)

    if args.check:
        print(json.dumps(status_payload(True, present=session_present(Path(args.output)))), flush=True)
        return 0

    if platform_name() not in ("linux", "darwin"):
        message = "This import supports Linux and macOS."
        if args.quiet:
            print(json.dumps(status_payload(False, error=message)), flush=True)
        else:
            eprint(message)
        return 2

    if args.list:
        for browser_id in OMARCHY_ORDER:
            meta = BROWSERS[browser_id]
            dbs = firefox_cookie_dbs(browser_id) if meta["kind"] == "firefox" else discover_chromium_cookie_dbs(browser_id)
            for db in dbs:
                print(browser_id, db)
        return 0

    quiet = bool(args.quiet)
    if not confirm_consent(quiet or args.yes):
        if quiet:
            print(json.dumps(status_payload(False, error="Import cancelled.")), flush=True)
        else:
            eprint("Cancelled.")
        return 1

    profile = args.profile.strip() or None
    browser_id = ""
    try:
        browser_id = resolve_browser(args.browser, profile)
        if not quiet:
            eprint("Reading", browser_name(browser_id))
        export_session(browser_id, profile, Path(args.output), announce=not quiet)
    except ExportError as exc:
        emit_status(status_payload(False, browser_id=browser_id, error=str(exc)), quiet)
        return 1
    except SystemExit as exc:
        message = exc.code if isinstance(exc.code, str) else "Import failed."
        emit_status(status_payload(False, error=str(message)), quiet)
        return 1
    emit_status(status_payload(True, browser_id=browser_id), quiet)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        eprint("Interrupted.")
        raise SystemExit(130)
