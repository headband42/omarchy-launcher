#!/usr/bin/env python3
"""Tests for the mail sampler. Stdlib only. A fake IMAP server on loopback
stands in for the provider, so imaplib's own parsing is exercised; nothing
here reaches the network or touches the real account list.

Run from the repo root:  python3 widgets/mail/test_mail.py
"""

import base64
import imaplib
import json
import os
import socketserver
import stat
import struct
import sys
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mail

GMAIL_CAPS = "IMAP4rev1 UNSELECT IDLE NAMESPACE X-GM-EXT-1 SASL-IR AUTH=PLAIN AUTH=XOAUTH2"
PLAIN_CAPS = "IMAP4rev1 SASL-IR AUTH=PLAIN"
LOGIN_CAPS = "IMAP4rev1"
HEADER_ITEM = "BODY[HEADER.FIELDS (FROM SUBJECT DATE)]"


def header(sender, subject, date="Fri, 02 Oct 2026 08:15:00 -0600"):
    return ("From: %s\r\nSubject: %s\r\nDate: %s\r\n\r\n" % (sender, subject, date)).encode("utf-8")


# uid -> what the server holds. Thread ids are the decimal X-GM-THRID.
MESSAGES = {
    3: {"flags": "", "date": "01-Oct-2026 22:00:00 -0600", "thrid": "1278455344230334865",
        "labels": '\\Inbox "\\\\Important"', "header": header('"Ada Lovelace" <ada@example.com>', "Engines")},
    5: {"flags": "\\Flagged", "date": "02-Oct-2026 08:15:00 -0600", "thrid": "1266894439832287888",
        "labels": '\\Inbox "Work (old)"', "header": header("=?UTF-8?B?SsO8cmdlbg==?= <j@example.de>", "=?UTF-8?Q?Gr=C3=BC=C3=9Fe?=")},
    9: {"flags": "", "date": " 2-Oct-2026 09:30:00 +0000", "thrid": "255",
        "labels": "\\Inbox", "header": header("bob@example.org", "Café tonight")},
}


class FakeImap(socketserver.StreamRequestHandler):
    """Just enough IMAP for the sampler, with the replies shaped like Gmail's."""

    def send(self, line):
        self.wfile.write(line.encode("utf-8") + b"\r\n")

    def handle(self):
        srv = self.server
        self.send("* OK [CAPABILITY %s] ready" % srv.caps)
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode("utf-8").rstrip("\r\n")
            srv.log.append(line)
            tag, _, rest = line.partition(" ")
            command = rest.split(" ", 1)[0].upper()
            if command == "CAPABILITY":
                self.send("* CAPABILITY " + srv.caps)
                self.send(tag + " OK done")
            elif command == "AUTHENTICATE":
                self.send("+ ")
                answer = base64.b64decode(self.rfile.readline().strip())
                _, user, password = answer.decode("utf-8").split("\0")
                self.signed_in(tag, user, password)
            elif command == "LOGIN":
                _, user, password = rest.split(" ", 2)
                self.signed_in(tag, user, password.strip('"'))
            elif command in ("EXAMINE", "SELECT"):
                self.send("* FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen)")
                self.send("* %d EXISTS" % len(srv.messages))
                self.send("* OK [UIDVALIDITY %d] UIDs valid." % srv.uidvalidity)
                self.send("%s OK [%s] %s" % (tag, "READ-ONLY" if command == "EXAMINE" else "READ-WRITE", "INBOX selected"))
            elif command == "UID":
                self.uid(tag, rest.split(" ", 2)[1].upper(), rest.split(" ", 2)[2])
            elif command == "LOGOUT":
                self.send("* BYE")
                self.send(tag + " OK bye")
                return
            else:
                self.send(tag + " BAD unknown")

    def signed_in(self, tag, user, password):
        srv = self.server
        srv.logins.append(user)
        if srv.refusal:
            self.send(tag + " NO " + srv.refusal)
        elif user == srv.user and password == srv.password:
            self.send(tag + " OK [CAPABILITY %s] signed in" % srv.caps)
        else:
            self.send(tag + " NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)")

    def uid(self, tag, sub, args):
        srv = self.server
        if sub == "SEARCH":
            srv.searches.append(args)
            self.send("* SEARCH " + " ".join(str(u) for u in sorted(srv.unread)))
            self.send(tag + " OK SEARCH completed")
        elif sub == "FETCH":
            uids, items = args.split(" ", 1)
            srv.fetches.append(items)
            gmail = "X-GM-THRID" in items
            for seq, uid in enumerate(sorted(int(u) for u in uids.split(",")), 1):
                m = srv.messages.get(uid)
                if not m:
                    continue
                parts = ["UID %d" % uid]
                if not srv.flags_last:
                    parts.append("FLAGS (%s)" % m["flags"])
                parts.append('INTERNALDATE "%s"' % m["date"])
                if gmail:
                    parts.append("X-GM-THRID %s X-GM-LABELS (%s)" % (m["thrid"], m["labels"]))
                head = "* %d FETCH (%s %s {%d}" % (seq, " ".join(parts), HEADER_ITEM, len(m["header"]))
                self.wfile.write(head.encode("utf-8") + b"\r\n" + m["header"])
                self.send(" FLAGS (%s))" % m["flags"] if srv.flags_last else ")")
            self.send(tag + " OK FETCH completed")
        elif sub == "STORE":
            srv.stores.append(args)
            uid = int(args.split(" ", 1)[0])
            if "\\Seen" in args and uid in srv.unread:
                srv.unread.remove(uid)
            self.send(tag + " OK STORE completed")
        else:
            self.send(tag + " BAD unknown")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, caps=GMAIL_CAPS, user="ada@gmail.com", password="abcdefghijklmnop"):
        super().__init__(("127.0.0.1", 0), FakeImap)
        self.caps = caps
        self.user = user
        self.password = password
        self.refusal = ""
        self.messages = dict(MESSAGES)
        self.unread = [3, 5, 9]
        self.uidvalidity = 7
        self.flags_last = False
        self.log, self.logins, self.searches, self.fetches, self.stores = [], [], [], [], []
        self.thread = threading.Thread(target=self.serve_forever, args=(0.02,), daemon=True)
        self.thread.start()

    def connector(self, host, port):
        self.dialed = (host, port)
        return imaplib.IMAP4("127.0.0.1", self.server_address[1], timeout=5)

    def stop(self):
        self.shutdown()
        self.server_close()


def account(**extra):
    row = {"id": "a1", "address": "ada@gmail.com", "user": "ada@gmail.com", "password": "abcdefghijklmnop",
           "host": "imap.gmail.com", "port": 993, "provider": "gmail", "view": "primary", "gmail": True}
    row.update(extra)
    return row


class ServerCase(unittest.TestCase):
    caps = GMAIL_CAPS
    user = "ada@gmail.com"

    def setUp(self):
        self.server = Server(self.caps, self.user)
        self.addCleanup(self.server.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, "config", "ande.launcher", "mail-accounts.json")
        self.cache = os.path.join(self.tmp.name, "cache", "mail.json")


class GmailTests(ServerCase):
    def test_reads_primary_without_changing_anything(self):
        result = mail.read_account(account(), self.server.connector)
        self.assertTrue(result["gmail"])
        self.assertEqual(result["unread"], 3)
        self.assertEqual(result["uidvalidity"], 7)
        commands = [line.split(" ", 2)[1].upper() for line in self.server.log]
        self.assertIn("EXAMINE", commands)
        self.assertNotIn("SELECT", commands)
        self.assertEqual(self.server.searches, ['X-GM-RAW "is:unread category:primary"'])
        self.assertIn("BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]", self.server.fetches[0])
        self.assertIn("X-GM-THRID", self.server.fetches[0])

    def test_messages_newest_first_with_links_and_decoded_headers(self):
        messages = mail.read_account(account(), self.server.connector)["messages"]
        # 08:15 in Denver is after 09:30 in London.
        self.assertEqual([m["uid"] for m in messages], [5, 9, 3])
        jurgen, bob, ada = messages
        self.assertEqual((ada["from"], ada["address"], ada["subject"]), ("Ada Lovelace", "ada@example.com", "Engines"))
        self.assertTrue(ada["important"])
        self.assertEqual((jurgen["from"], jurgen["subject"]), ("Jürgen", "Grüße"))
        self.assertTrue(jurgen["flagged"])
        self.assertFalse(jurgen["important"])
        self.assertEqual((bob["from"], bob["subject"]), ("bob", "Café tonight"))
        self.assertEqual(bob["date"], int(datetime(2026, 10, 2, 9, 30, tzinfo=timezone.utc).timestamp()))
        self.assertEqual(ada["link"], "https://mail.google.com/mail/u/?authuser=ada%40gmail.com#inbox/" + format(1278455344230334865, "x"))

    def test_flags_after_the_literal(self):
        self.server.flags_last = True
        messages = mail.read_account(account(), self.server.connector)["messages"]
        self.assertTrue(next(m for m in messages if m["uid"] == 5)["flagged"])

    def test_inbox_and_important_views(self):
        mail.read_account(account(view="inbox"), self.server.connector)
        mail.read_account(account(view="important"), self.server.connector)
        self.assertEqual(self.server.searches, ["UNSEEN", 'X-GM-RAW "is:unread is:important"'])

    def test_only_the_newest_are_fetched(self):
        self.server.unread = list(range(1, 41))
        result = mail.read_account(account(), self.server.connector, limit=15)
        self.assertEqual(result["unread"], 40)
        self.assertTrue(self.server.fetches[0] and self.server.log[-2].split(" ")[3].startswith("26,27"))

    def test_wrong_password(self):
        with self.assertRaises(mail.MailError) as caught:
            mail.read_account(account(password="nope"), self.server.connector)
        self.assertEqual((caught.exception.state, caught.exception.message), ("auth", "Wrong address or app password"))

    def test_account_password_instead_of_app_password(self):
        self.server.refusal = "[ALERT] Application-specific password required: https://support.google.com/accounts/answer/185833 (Failure)"
        with self.assertRaises(mail.MailError) as caught:
            mail.read_account(account(), self.server.connector)
        self.assertEqual(caught.exception.message, "Use an app password, not the account's own password")

    def test_mark_read_checks_uidvalidity(self):
        mail.write_saved([account()], self.path)
        self.assertEqual(mail.mark_read("a1", "7", "5", self.path, self.server.connector), {"ok": True})
        self.assertEqual(self.server.stores, ["5 +FLAGS.SILENT (\\Seen)"])
        self.assertIn("SELECT", [line.split(" ", 2)[1].upper() for line in self.server.log])
        refused = mail.mark_read("a1", "8", "5", self.path, self.server.connector)
        self.assertFalse(refused["ok"])
        self.assertEqual(len(self.server.stores), 1)
        self.assertFalse(mail.mark_read("a1", "7", "5 6", self.path, self.server.connector)["ok"])
        self.assertFalse(mail.mark_read("zz", "7", "5", self.path, self.server.connector)["ok"])


class PlainImapTests(ServerCase):
    caps = PLAIN_CAPS
    user = "me@example.net"

    def test_unseen_and_no_gmail_items(self):
        result = mail.read_account(account(address="me@example.net", user="me@example.net", provider="other", gmail=False), self.server.connector)
        self.assertFalse(result["gmail"])
        self.assertEqual(self.server.searches, ["UNSEEN"])
        self.assertNotIn("X-GM", self.server.fetches[0])
        self.assertTrue(all(m["link"] == "" for m in result["messages"]))

    def test_login_when_there_is_no_auth_plain(self):
        self.server.caps = LOGIN_CAPS
        mail.read_account(account(address="me@example.net", user="me@example.net", provider="other"), self.server.connector)
        self.assertTrue(any(" LOGIN " in line for line in self.server.log))


class AddTests(ServerCase):
    def test_add_saves_privately_and_never_echoes_the_password(self):
        self.server.user = "Ada@gmail.com"
        result = mail.add("Ada@Gmail.com", "abcd efgh ijkl mnop", path=self.path, connector=self.server.connector)
        self.assertTrue(result["ok"], result)
        self.assertNotIn("abcdefghijklmnop", json.dumps(result))
        self.assertEqual(result["account"]["view"], "primary")
        self.assertEqual(result["account"]["provider"], "gmail")
        self.assertEqual(result["unread"], 3)
        self.assertEqual(self.server.fetches, [])
        self.assertEqual(self.server.dialed, ("imap.gmail.com", 993))
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(self.path)).st_mode), 0o700)
        saved = mail.read_saved(self.path)
        self.assertEqual((saved[0]["address"], saved[0]["password"]), ("Ada@gmail.com", "abcdefghijklmnop"))
        again = mail.add("ada@gmail.com", "abcdefghijklmnop", path=self.path, connector=self.server.connector)
        self.assertEqual(again, {"ok": False, "error": "That account is already on the tile"})
        self.assertNotIn("abcdefghijklmnop", json.dumps(mail.listing(mail.read_saved(self.path))))

    def test_a_workspace_domain_found_by_mx_counts_the_whole_inbox(self):
        self.server.user = "ada@example.com"
        result = mail.add("ada@example.com", "abcdefghijklmnop", path=self.path, connector=self.server.connector,
                          mx=lambda domain: ["aspmx.l.google.com"])
        self.assertTrue(result["ok"], result)
        self.assertEqual((result["account"]["provider"], result["account"]["view"]), ("gmail", "inbox"))
        self.assertTrue(result["account"]["gmail"])

    def test_a_failed_sign_in_saves_nothing(self):
        result = mail.add("ada@gmail.com", "wrong", path=self.path, connector=self.server.connector)
        self.assertEqual(result, {"ok": False, "error": "Wrong address or app password"})
        self.assertFalse(os.path.exists(self.path))

    def test_icloud_tries_the_name_then_the_whole_address(self):
        self.server.caps = PLAIN_CAPS
        self.server.user = "ada@icloud.com"
        self.server.password = "abcd-efgh-ijkl-mnop"
        result = mail.add("ada@icloud.com", "abcd-efgh-ijkl-mnop", path=self.path, connector=self.server.connector)
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.server.logins, ["ada", "ada@icloud.com"])
        self.assertEqual(mail.read_saved(self.path)[0]["user"], "ada@icloud.com")
        self.assertEqual(mail.read_saved(self.path)[0]["password"], "abcd-efgh-ijkl-mnop")

    def test_refused_without_connecting(self):
        for address, words in (("me@outlook.com", "Microsoft sign-in"), ("me@hotmail.co.uk", "Microsoft sign-in"),
                               ("me@hey.com", "HEY"), ("me@tuta.com", "Tuta")):
            result = mail.add(address, "x", path=self.path, connector=self.server.connector, mx=lambda d: [])
            self.assertFalse(result["ok"])
            self.assertIn(words, result["error"])
        hey_domain = mail.add("me@omarchy.example", "x", path=self.path, connector=self.server.connector,
                              mx=lambda d: ["work-mx.app.hey.com"])
        self.assertIn("HEY", hey_domain["error"])
        self.assertEqual(self.server.logins, [])

    def test_unknown_domain_asks_for_the_server(self):
        result = mail.add("me@small.example", "x", path=self.path, connector=self.server.connector, mx=lambda d: [])
        self.assertIn("Type its IMAP server, like imap.small.example", result["error"])
        self.server.caps = PLAIN_CAPS
        self.server.user = "me@small.example"
        self.server.password = "pw"
        typed = mail.add("me@small.example", "pw", "mail.small.example:143", path=self.path,
                         connector=self.server.connector, mx=lambda d: [])
        self.assertTrue(typed["ok"], typed)
        self.assertEqual(self.server.dialed, ("mail.small.example", 143))
        self.assertEqual((typed["account"]["provider"], typed["account"]["where"]), ("other", "mail.small.example:143"))

    def test_bad_input(self):
        self.assertEqual(mail.add("nope", "x", path=self.path)["error"], "That isn't an email address")
        self.assertEqual(mail.add("a@b.co", "  ", path=self.path)["error"], "Paste the app password too")
        bad = mail.add("a@b.co", "x", "imap.b.co;rm", path=self.path, mx=lambda d: [])
        self.assertIn("isn't a host name", bad["error"])

    def test_remove_and_view(self):
        mail.write_saved([account(), account(id="b2", address="me@example.net", gmail=False, view="inbox")], self.path)
        self.assertEqual(mail.set_view("a1", "inbox", self.path)["account"]["view"], "inbox")
        self.assertFalse(mail.set_view("b2", "primary", self.path)["ok"])
        self.assertFalse(mail.set_view("a1", "spam", self.path)["ok"])
        self.assertTrue(mail.remove("a1", self.path)["ok"])
        self.assertFalse(mail.remove("a1", self.path)["ok"])
        self.assertEqual([a["id"] for a in mail.read_saved(self.path)], ["b2"])


class CollectTests(ServerCase):
    def test_collect_and_cache(self):
        payload = mail.collect([account()], self.server.connector, cache=self.cache, now=1_000_000)
        self.assertEqual(payload["unread"], 3)
        row = payload["accounts"][0]
        self.assertTrue(row["ok"])
        self.assertEqual(row["web"], "https://mail.google.com/mail/u/?authuser=ada%40gmail.com")
        self.assertNotIn("password", row)
        mail.write_cache(payload, self.cache)
        self.assertEqual(stat.S_IMODE(os.stat(self.cache).st_mode), 0o600)
        with open(self.cache, encoding="utf-8") as handle:
            self.assertNotIn("abcdefghijklmnop", handle.read())

    def test_a_failing_account_shows_its_last_mail_for_a_day(self):
        mail.write_cache(mail.collect([account()], self.server.connector, cache=self.cache, now=1_000_000), self.cache)
        self.server.refusal = "[AUTHENTICATIONFAILED] Invalid credentials (Failure)"
        later = mail.collect([account()], self.server.connector, cache=self.cache, now=1_000_000 + 3600)
        row = later["accounts"][0]
        self.assertEqual((row["ok"], row["stale"], row["state"], row["unread"]), (False, True, "auth", 3))
        self.assertEqual(row["at"], 1_000_000)
        mail.write_cache(later, self.cache)
        again = mail.collect([account()], self.server.connector, cache=self.cache, now=1_000_000 + 7200)
        self.assertTrue(again["accounts"][0]["stale"])
        expired = mail.collect([account()], self.server.connector, cache=self.cache, now=1_000_000 + mail.STALE_MAX + 1)
        self.assertEqual((expired["accounts"][0]["stale"], expired["accounts"][0]["messages"]), (False, []))

    def test_no_accounts(self):
        self.assertEqual(mail.collect([], self.server.connector, cache=self.cache)["accounts"], [])

    def test_offline(self):
        def down(host, port):
            raise mail.MailError("offline", "Can't reach %s" % host)
        row = mail.collect([account()], down, cache=self.cache)["accounts"][0]
        self.assertEqual((row["state"], row["error"]), ("offline", "Can't reach imap.gmail.com"))

    def test_main_never_prints_a_password(self):
        mail.write_saved([account()], self.path)
        with mock.patch.object(mail, "config_path", return_value=self.path), \
                mock.patch("sys.stdout") as out:
            mail.main(["mail.py", "--list"])
        printed = "".join(call.args[0] for call in out.write.call_args_list)
        self.assertIn("ada@gmail.com", printed)
        self.assertNotIn("abcdefghijklmnop", printed)


class ValueTests(unittest.TestCase):
    def test_app_password_spaces(self):
        self.assertEqual(mail.clean_password(" abcd efgh ijkl mnop "), "abcdefghijklmnop")
        self.assertEqual(mail.clean_password("my pass word"), "my pass word")
        self.assertEqual(mail.clean_password("abcd-efgh-ijkl-mnop"), "abcd-efgh-ijkl-mnop")

    def test_addresses(self):
        self.assertEqual(mail.clean_address("mailto:Ada@Example.COM"), "Ada@example.com")
        self.assertEqual(mail.clean_address("ada@localhost"), "")
        self.assertEqual(mail.clean_address('a"b@x.com'), "")

    def test_servers(self):
        self.assertEqual(mail.parse_server("imap.example.com"), ("imap.example.com", 993))
        self.assertEqual(mail.parse_server("IMAPS://Mail.Example.com:143/"), ("mail.example.com", 143))
        self.assertEqual(mail.parse_server("127.0.0.1:1143"), ("127.0.0.1", 1143))
        self.assertEqual(mail.parse_server("[::1]:1143"), ("[::1]", 1143))
        self.assertEqual(mail.parse_server("host:99999"), ("", 0))
        self.assertEqual(mail.parse_server("a b"), ("", 0))

    def test_providers(self):
        self.assertEqual(mail.resolve("a@yahoo.co.uk")["host"], "imap.mail.yahoo.com")
        self.assertEqual(mail.resolve("a@me.com")["provider"], "icloud")
        self.assertEqual(mail.resolve("a@gmx.de")["host"], "imap.gmx.net")
        self.assertEqual(mail.resolve("a@zohomail.eu")["host"], "imap.zoho.eu")
        self.assertEqual(mail.resolve("a@corp.example", mx=lambda d: ["mx.zoho.eu"])["host"], "imappro.zoho.eu")
        self.assertEqual(mail.resolve("a@corp.example", mx=lambda d: ["in1-smtp.messagingengine.com"])["provider"], "fastmail")
        proton = mail.resolve("a@proton.me")
        self.assertEqual((proton["host"], proton["port"]), ("127.0.0.1", 1143))
        with self.assertRaises(mail.MailError):
            mail.resolve("a@corp.example", mx=lambda d: ["corp-example.mail.protection.outlook.com"])
        with self.assertRaises(mail.MailError):
            mail.resolve("a@corp.example", "outlook.office365.com")
        # DavMail on this machine speaks IMAP for an Exchange account.
        self.assertEqual(mail.resolve("a@outlook.com", "localhost:1143")["provider"], "other")

    def test_loopback(self):
        self.assertTrue(mail.is_loopback("127.0.0.1"))
        self.assertTrue(mail.is_loopback("[::1]"))
        self.assertTrue(mail.is_loopback("localhost"))
        self.assertFalse(mail.is_loopback("imap.gmail.com"))

    def test_login_failures(self):
        self.assertEqual(mail.login_failure("[ALERT] Please log in via your web browser: https://x (Failure)"),
                         "Sign in once on the web, then try again")
        self.assertEqual(mail.login_failure("[ALERT] Your account is not enabled for IMAP use."), "IMAP is turned off for this account")
        self.assertEqual(mail.login_failure("LOGIN failed."), "Wrong address or app password")
        self.assertEqual(mail.login_failure("Something else"), "Something else")

    def test_two_literals_in_one_reply(self):
        data = [
            (b'1 (UID 4 X-GM-LABELS ({9}', b'Big "one"'),
            (b' \\Inbox) BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {33}', b"From: a@b.c\r\nSubject: Hi there\r\n\r\n"),
            b' FLAGS (\\Seen \\Flagged))',
            b'2 (FLAGS (\\Seen))',
        ]
        chunks = mail.responses(data)
        self.assertEqual(len(chunks), 2)
        items = mail.fetch_items(chunks[0])
        self.assertEqual(items["UID"], "4")
        self.assertEqual(items["X-GM-LABELS"], [b'Big "one"', "\\Inbox"])
        self.assertEqual(items["FLAGS"], ["\\Seen", "\\Flagged"])
        self.assertEqual(mail.header_fields(items["BODY[HEADER]"])[2], "Hi there")
        self.assertIsNone(mail.message_of(mail.fetch_items(chunks[1]), account()))

    def test_internal_date(self):
        self.assertEqual(mail.internal_date("02-Oct-2026 08:15:00 -0600"),
                         int(datetime(2026, 10, 2, 14, 15, tzinfo=timezone.utc).timestamp()))
        self.assertIsNone(mail.internal_date("yesterday"))

    def test_mangled_headers(self):
        name, address, subject, sent = mail.header_fields(b"From: \r\nSubject: =?bogus?Q?x?=\r\nDate: not a date\r\n\r\n")
        self.assertEqual((name, sent), ("Unknown sender", None))
        self.assertTrue(subject)


def dns_reply(ident, answers, rcode=0):
    """A reply to an MX query for example.com, answers compressed against the question."""
    question = b"\x07example\x03com\x00" + struct.pack(">HH", 15, 1)
    body = b""
    for preference, host in answers:
        labels = host.split(".")
        name = b"".join(bytes([len(l)]) + l.encode() for l in labels[:-2]) + b"\xc0\x0c"
        rdata = struct.pack(">H", preference) + name
        body += b"\xc0\x0c" + struct.pack(">HHIH", 15, 1, 300, len(rdata)) + rdata
    return struct.pack(">HHHHHH", ident, 0x8180 | rcode, 1, len(answers), 0, 0) + question + body


class DnsTests(unittest.TestCase):
    def test_mx_in_preference_order(self):
        reply = dns_reply(42, [(20, "alt.example.com"), (10, "mx.example.com")])
        self.assertEqual(mail.parse_mx(reply, 42), ["mx.example.com", "alt.example.com"])

    def test_wrong_id_or_error(self):
        self.assertEqual(mail.parse_mx(dns_reply(42, [(10, "mx.example.com")]), 43), [])
        self.assertEqual(mail.parse_mx(dns_reply(42, [], rcode=3), 42), [])

    def test_query_shape(self):
        packet = mail.dns_query("example.com", 7)
        self.assertEqual(packet[:2], b"\x00\x07")
        self.assertTrue(packet.endswith(b"\x07example\x03com\x00\x00\x0f\x00\x01"))

    def test_resolvers(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            handle.write("# comment\nnameserver 127.0.0.53\nnameserver fe80::1%eth0\noptions edns0\n")
        self.addCleanup(os.remove, handle.name)
        self.assertEqual(mail.resolvers(handle.name), ["127.0.0.53", "fe80::1"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
