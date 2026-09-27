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


if __name__ == "__main__":
    raise SystemExit(unittest.main())
