#!/usr/bin/env python3
"""Tests for export-browser-cookies.py (no live browser required)."""

from __future__ import annotations

import hashlib
import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import importlib.util

_SPEC = importlib.util.spec_from_file_location(
    "export_browser_cookies",
    Path(__file__).resolve().parent / "export-browser-cookies.py",
)
exp = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(exp)


def _encrypt_v10(plaintext: bytes, password: bytes = b"peanuts", iterations: int = 1) -> bytes:
    key = hashlib.pbkdf2_hmac("sha1", password, b"saltysalt", iterations, dklen=16)
    iv = b" " * 16
    pad = 16 - (len(plaintext) % 16)
    padded = plaintext + bytes([pad] * pad)
    cipher = subprocess.check_output(
        ["openssl", "enc", "-aes-128-cbc", "-e", "-K", key.hex(), "-iv", iv.hex(), "-nopad"],
        input=padded,
    )
    return b"v10" + cipher


class ExportCookiesTest(unittest.TestCase):
    def test_host_matches(self):
        self.assertTrue(exp.host_matches(".x.com"))
        self.assertTrue(exp.host_matches("x.com"))
        self.assertTrue(exp.host_matches(".twitter.com"))
        self.assertFalse(exp.host_matches("example.com"))

    def test_decrypt_chromium_with_domain_tag(self):
        host = ".x.com"
        value = "token-abc"
        plain = hashlib.sha256(host.encode()).digest() + value.encode()
        blob = _encrypt_v10(plain)
        key = hashlib.pbkdf2_hmac("sha1", b"peanuts", b"saltysalt", 1, dklen=16)
        out = exp.decrypt_chromium_value(blob, key, db_version=24, host_key=host)
        self.assertEqual(out, value)

    def test_read_firefox_cookies(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "cookies.sqlite"
            conn = sqlite3.connect(str(db))
            conn.execute(
                "CREATE TABLE moz_cookies (host TEXT, name TEXT, value TEXT)"
            )
            conn.executemany(
                "INSERT INTO moz_cookies VALUES (?, ?, ?)",
                [
                    (".x.com", "auth_token", "atk"),
                    (".x.com", "ct0", "csrf"),
                    (".example.com", "auth_token", "nope"),
                ],
            )
            conn.commit()
            conn.close()
            found = exp.read_firefox_cookies(db)
            self.assertEqual(found, {"auth_token": "atk", "ct0": "csrf"})

    def test_read_chromium_cookies_peanuts(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "Cookies"
            conn = sqlite3.connect(str(db))
            conn.execute("CREATE TABLE meta (key TEXT, value TEXT)")
            conn.execute("INSERT INTO meta VALUES ('version', '24')")
            conn.execute(
                "CREATE TABLE cookies (host_key TEXT, name TEXT, encrypted_value BLOB, value TEXT)"
            )
            host = ".x.com"
            for name, value in (("auth_token", "atk-chrome"), ("ct0", "csrf-chrome")):
                plain = hashlib.sha256(host.encode()).digest() + value.encode()
                enc = _encrypt_v10(plain)
                conn.execute(
                    "INSERT INTO cookies VALUES (?, ?, ?, ?)",
                    (host, name, enc, ""),
                )
            conn.commit()
            conn.close()

            with patch.object(exp, "chromium_password", return_value=(b"peanuts", 1)):
                found = exp.read_chromium_cookies(db, "chromium")
            self.assertEqual(found["auth_token"], "atk-chrome")
            self.assertEqual(found["ct0"], "csrf-chrome")

    def test_write_output_chmod_and_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "ande.launcher" / "x-cookies.json"
            exp.write_output(out, {"auth_token": "a", "ct0": "b"})
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data, {"auth_token": "a", "ct0": "b"})
            mode = out.stat().st_mode & 0o777
            self.assertEqual(mode, 0o600)

    def test_write_output_requires_both(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "x-cookies.json"
            with self.assertRaises(SystemExit):
                exp.write_output(out, {"auth_token": "only"})

    def test_omarchy_browsers_are_supported(self):
        self.assertEqual(
            exp.OMARCHY_ORDER,
            ("chromium", "chrome", "brave", "brave-origin", "edge", "firefox", "zen"),
        )
        for browser_id in exp.OMARCHY_ORDER:
            self.assertIn(browser_id, exp.BROWSERS)
            self.assertTrue(exp.browser_roots(browser_id, "linux"))
            self.assertTrue(exp.browser_roots(browser_id, "darwin"))

    def test_normalize_browser_id(self):
        self.assertEqual(exp.normalize_browser_id("brave-origin"), "brave-origin")
        self.assertEqual(exp.normalize_browser_id("BRAVE-ORIGIN"), "brave-origin")
        self.assertEqual(exp.normalize_browser_id("zen.desktop"), "zen")
        self.assertEqual(exp.normalize_browser_id("microsoft-edge.desktop"), "edge")
        self.assertEqual(exp.normalize_browser_id("google-chrome.desktop"), "chrome")
        self.assertEqual(exp.normalize_browser_id("brave-browser.desktop"), "brave")
        self.assertEqual(exp.normalize_browser_id(""), "")

    def test_resolve_browser_prefers_omarchy_default(self):
        with patch.object(exp, "omarchy_default_browser", return_value="brave-origin"):
            self.assertEqual(exp.resolve_browser("auto", None), "brave-origin")
        with patch.object(exp, "omarchy_default_browser", return_value=""):
            with patch.object(exp, "browser_has_store", side_effect=lambda browser: browser == "zen"):
                self.assertEqual(exp.resolve_browser("auto", None), "zen")

    def test_pick_keyring_item_distinguishes_same_label(self):
        items = [
            {"label": "Chromium Safe Storage", "application": "Code"},
            {"label": "Chromium Safe Storage", "application": "chromium"},
            {"label": "Brave Safe Storage", "application": "brave"},
        ]
        chosen = exp.pick_keyring_item(items, "Chromium Safe Storage", ("chromium",))
        self.assertEqual(chosen["application"], "chromium")
        brave = exp.pick_keyring_item(items, "Brave Safe Storage", ("brave",))
        self.assertEqual(brave["application"], "brave")
        self.assertIsNone(exp.pick_keyring_item(items, "Chromium Safe Storage", ("microsoft-edge",)))

    def test_prefers_network_cookies_in_default_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Default" / "Network").mkdir(parents=True)
            (root / "Default" / "Network" / "Cookies").write_bytes(b"n")
            (root / "Default" / "Cookies").write_bytes(b"old")
            (root / "Profile 1").mkdir()
            (root / "Profile 1" / "Cookies").write_bytes(b"p")
            with patch.object(exp, "browser_roots", return_value=(root,)):
                found = exp.discover_chromium_cookie_dbs("brave-origin")
            self.assertEqual(found[0], root / "Default" / "Network" / "Cookies")
            self.assertEqual(found[1], root / "Profile 1" / "Cookies")
            self.assertNotIn(root / "Default" / "Cookies", found)

    def test_firefox_profile_ini_picks_install_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            default = root / "abc.default-release"
            other = root / "zzz.other"
            default.mkdir()
            other.mkdir()
            (default / "cookies.sqlite").write_bytes(b"")
            (other / "cookies.sqlite").write_bytes(b"")
            (root / "profiles.ini").write_text(
                "[Install1]\nDefault=abc.default-release\n\n"
                "[Profile0]\nName=other\nIsRelative=1\nPath=zzz.other\n\n"
                "[Profile1]\nName=default-release\nIsRelative=1\nPath=abc.default-release\nDefault=1\n",
                encoding="utf-8",
            )
            with patch.object(exp, "browser_roots", return_value=(root,)):
                found = exp.firefox_cookie_dbs("zen")
            self.assertEqual(found[0], default / "cookies.sqlite")

    def test_quiet_export_prints_status_without_secrets(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "x-cookies.json"
            with patch.object(exp, "resolve_browser", return_value="zen"), patch.object(
                exp,
                "read_browser_cookies",
                return_value=({"auth_token": "secret-token", "ct0": "secret-ct0"}, Path(tmp)),
            ):
                code, payload, stdout, stderr = _run_main(
                    ["--quiet", "--browser", "zen", "-o", str(out)]
                )
            self.assertEqual(code, 0)
            self.assertTrue(payload["ok"])
            self.assertEqual(payload["browser"], "zen")
            self.assertEqual(payload["browserName"], "Zen")
            self.assertNotIn("secret-token", stdout)
            self.assertNotIn("secret-token", stderr)
            saved = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(saved["auth_token"], "secret-token")
            self.assertEqual(oct(out.stat().st_mode & 0o777), "0o600")

    def test_quiet_missing_session_is_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "x-cookies.json"
            with patch.object(exp, "resolve_browser", return_value="edge"), patch.object(
                exp,
                "read_browser_cookies",
                return_value=({}, None),
            ):
                code, payload, stdout, _stderr = _run_main(
                    ["--quiet", "--browser", "edge", "-o", str(out)]
                )
            self.assertEqual(code, 1)
            self.assertFalse(payload["ok"])
            self.assertIn("Edge", payload["error"])
            self.assertNotIn("auth_token", stdout)
            self.assertFalse(out.exists())


def _run_main(argv):
    import io
    from contextlib import redirect_stderr, redirect_stdout

    stdout = io.StringIO()
    stderr = io.StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        code = exp.main(argv)
    raw = stdout.getvalue()
    payload = json.loads(raw) if raw.strip() else {}
    return code, payload, raw, stderr.getvalue()


if __name__ == "__main__":
    raise SystemExit(unittest.main())
