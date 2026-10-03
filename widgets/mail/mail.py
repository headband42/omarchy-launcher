#!/usr/bin/env python3
"""Unread mail over IMAP, for the launcher tile. Stdlib only.

    mail.py                        the tile: unread mail in every saved account
    mail.py --list                 the settings panel: the saved accounts
    mail.py --add                  the settings panel: sign in to $ANDE_MAIL_ADDRESS
                                   with $ANDE_MAIL_PASSWORD (at $ANDE_MAIL_SERVER
                                   when set) and save it once that works
    mail.py --remove ID            forget one account
    mail.py --view ID VIEW         what a Gmail account counts: primary, inbox, important
    mail.py --read ID UIDVALIDITY UID
                                   mark one message read

Every provider that takes an app password over IMAP works the same way: Gmail
and Google Workspace, iCloud, Fastmail, Yahoo, AOL, Zoho, GMX, mail.com,
WEB.DE, Yandex, mailbox.org, Posteo, Proton through Proton Mail Bridge, and any
other IMAP server. The server comes from the address, then from the domain's
MX records (a Google Workspace or Fastmail custom domain), or the user types it.
Outlook, Hotmail, and Microsoft 365 are refused: since September 2024 they take
only a Microsoft OAuth sign-in, app passwords included. HEY and Tuta have no
IMAP at all.

A Gmail server (one that says X-GM-EXT-1) gets three extras: the count can be
the Primary tab, the whole inbox, or Important (X-GM-RAW, Gmail's own search),
a row links to its conversation on mail.google.com (X-GM-THRID in hex), and the
account is picked there by ?authuser=.

Reading never changes a message: the inbox is opened with EXAMINE and headers
are fetched with BODY.PEEK. Only --read writes, one \\Seen flag, and only while
the inbox's UIDVALIDITY still matches the one the row came from.

An app password is a password, so the accounts live in
$XDG_CONFIG_HOME/ande.launcher/mail-accounts.json at mode 0600, never in the
launcher's config or on a command line; the panel hands a new one over in the
environment. The password is never printed. A password only goes over TLS
(port 993, or STARTTLS), and the certificate is checked, except on this
machine's own loopback, where Proton Mail Bridge listens with a self-signed one.

The last good reply is kept in $XDG_CACHE_HOME/ande.launcher/mail.json (0600,
no passwords) so the tile draws at once, and an account that stops answering
shows its last mail, marked stale, for up to a day.
"""

import email.utils
import imaplib
import ipaddress
import json
import os
import random
import re
import secrets
import socket
import ssl
import struct
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from email import policy
from email.header import decode_header
from email.parser import BytesHeaderParser
from urllib.parse import quote

TIMEOUT = 15
DNS_TIMEOUT = 3
MAX_ACCOUNTS = 4
PER_ACCOUNT = 15
STALE_MAX = 86400
ADDRESS_ENV = "ANDE_MAIL_ADDRESS"
PASSWORD_ENV = "ANDE_MAIL_PASSWORD"
SERVER_ENV = "ANDE_MAIL_SERVER"
VIEWS = ("primary", "inbox", "important")
GMAIL_QUERIES = {"primary": "is:unread category:primary", "important": "is:unread is:important"}
HEADER_ITEM = "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]"

PROVIDERS = {
    "gmail": {"name": "Gmail", "host": "imap.gmail.com", "port": 993, "web": "https://mail.google.com/mail/u/?authuser={address}"},
    "icloud": {"name": "iCloud", "host": "imap.mail.me.com", "port": 993, "web": "https://www.icloud.com/mail/"},
    "fastmail": {"name": "Fastmail", "host": "imap.fastmail.com", "port": 993, "web": "https://app.fastmail.com/mail/Inbox/"},
    "yahoo": {"name": "Yahoo", "host": "imap.mail.yahoo.com", "port": 993, "web": "https://mail.yahoo.com/"},
    "aol": {"name": "AOL", "host": "imap.aol.com", "port": 993, "web": "https://mail.aol.com/"},
    "zoho": {"name": "Zoho", "host": "imap.zoho.com", "port": 993, "web": "https://mail.zoho.com/"},
    "gmx": {"name": "GMX", "host": "imap.gmx.com", "port": 993, "web": "https://www.gmx.com/"},
    "gmxnet": {"name": "GMX", "host": "imap.gmx.net", "port": 993, "web": "https://www.gmx.net/"},
    "mailcom": {"name": "mail.com", "host": "imap.mail.com", "port": 993, "web": "https://www.mail.com/"},
    "webde": {"name": "WEB.DE", "host": "imap.web.de", "port": 993, "web": "https://web.de/"},
    "yandex": {"name": "Yandex", "host": "imap.yandex.com", "port": 993, "web": "https://mail.yandex.com/"},
    "mailbox": {"name": "mailbox.org", "host": "imap.mailbox.org", "port": 993, "web": "https://login.mailbox.org/"},
    "posteo": {"name": "Posteo", "host": "posteo.de", "port": 993, "web": "https://posteo.de/"},
    "proton": {"name": "Proton", "host": "127.0.0.1", "port": 1143, "web": "https://mail.proton.me/"},
    "other": {"name": "Mail", "host": "", "port": 993, "web": ""},
}

DOMAINS = {
    "gmail.com": "gmail", "googlemail.com": "gmail",
    "icloud.com": "icloud", "me.com": "icloud", "mac.com": "icloud",
    "fastmail.com": "fastmail", "fastmail.fm": "fastmail", "fastmail.us": "fastmail", "fastmail.net": "fastmail",
    "fastmail.org": "fastmail", "fastmail.to": "fastmail", "fastmail.in": "fastmail", "sent.com": "fastmail",
    "messagingengine.com": "fastmail",
    "ymail.com": "yahoo", "rocketmail.com": "yahoo",
    "aol.com": "aol", "aim.com": "aol",
    "zohomail.com": "zoho", "zoho.com": "zoho",
    "gmx.com": "gmx", "gmx.us": "gmx", "gmx.co.uk": "gmx",
    "gmx.net": "gmxnet", "gmx.de": "gmxnet", "gmx.at": "gmxnet", "gmx.ch": "gmxnet",
    "mail.com": "mailcom", "email.com": "mailcom", "usa.com": "mailcom", "post.com": "mailcom",
    "web.de": "webde",
    "yandex.com": "yandex", "yandex.ru": "yandex", "ya.ru": "yandex",
    "mailbox.org": "mailbox",
    "posteo.de": "posteo", "posteo.net": "posteo", "posteo.org": "posteo", "posteo.eu": "posteo",
    "proton.me": "proton", "protonmail.com": "proton", "protonmail.ch": "proton", "pm.me": "proton",
}

# Zoho's personal addresses and its regions' servers. A custom domain on Zoho
# is an organization account, which signs in at imappro instead.
ZOHO_REGIONS = {"zohomail.eu": "eu", "zoho.eu": "eu", "zohomail.in": "in", "zoho.in": "in",
                "zohomail.com.au": "com.au", "zoho.com.au": "com.au"}

REFUSED = {
    "microsoft": "Outlook, Hotmail, and Microsoft 365 take only a Microsoft sign-in now, not an app password, so the tile can't read them",
    "hey": "HEY has no IMAP, so the tile can't read it",
    "tuta": "Tuta has no IMAP, so the tile can't read it",
}
REFUSED_DOMAINS = {
    "hey.com": "hey",
    "tuta.com": "tuta", "tuta.io": "tuta", "tutanota.com": "tuta", "tutanota.de": "tuta", "tutamail.com": "tuta",
    "keemail.me": "tuta",
}

# What a custom domain's MX records say about where its mail lives.
MX_RULES = (
    ("google.com", "gmail"), ("googlemail.com", "gmail"),
    ("messagingengine.com", "fastmail"),
    ("mail.icloud.com", "icloud"),
    ("protonmail.ch", "proton"),
    ("zoho.com", "zoho"), ("zoho.eu", "zoho"), ("zoho.in", "zoho"), ("zoho.com.au", "zoho"),
    ("mailbox.org", "mailbox"),
    ("yandex.net", "yandex"), ("yandex.ru", "yandex"),
    ("outlook.com", "microsoft"),
    ("hey.com", "hey"),
)

ADDRESS = re.compile(r"[^@\s\"'<>\\`]{1,64}@([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}")
HOST = re.compile(r"[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*|\[[0-9a-f:]+\]")
APP_PASSWORD = re.compile(r"[a-z]{4}( [a-z]{4}){3}")
MONTHS = {m: i + 1 for i, m in enumerate(("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"))}


class MailError(Exception):
    """A failure the tile can name. `state` is auth, offline, tls, or error."""

    def __init__(self, state, message):
        super().__init__(message)
        self.state = state
        self.message = message


def one_line(value, limit=160):
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


# —— Where the account lives ——


def domain_of(address):
    return address.rsplit("@", 1)[1] if "@" in address else ""


def clean_address(raw):
    value = str(raw or "").strip()
    if value.lower().startswith("mailto:"):
        value = value[7:]
    if "@" not in value:
        return ""
    local, domain = value.rsplit("@", 1)
    value = local + "@" + domain.lower().rstrip(".")
    return value if len(value) <= 254 and ADDRESS.fullmatch(value) else ""


def clean_password(raw):
    """The password as typed, without the spaces Google and Yahoo print
    between the four-letter groups of an app password."""
    value = str(raw or "").strip()
    return value.replace(" ", "") if APP_PASSWORD.fullmatch(value) else value


def provider_for_domain(domain):
    """A provider id for an address's own domain, "microsoft" and the like for
    one the tile refuses, or ""."""
    if domain in DOMAINS:
        return DOMAINS[domain]
    if domain in ZOHO_REGIONS:
        return "zoho"
    if domain in REFUSED_DOMAINS:
        return REFUSED_DOMAINS[domain]
    first = domain.split(".", 1)[0]
    if first in ("outlook", "hotmail", "live", "msn", "passport", "windowslive"):
        return "microsoft"
    if first == "yahoo" and domain != "yahoo.co.jp":
        return "yahoo"
    return ""


def provider_for_mx(hosts):
    for host in hosts:
        for suffix, provider in MX_RULES:
            if host == suffix or host.endswith("." + suffix):
                return provider, host
    return "", ""


def zoho_host(domain, mx_host=""):
    """Zoho's server for a personal address or, through its MX, a custom domain."""
    if domain in ZOHO_REGIONS or domain in ("zohomail.com", "zoho.com"):
        region = ZOHO_REGIONS.get(domain, "com")
        return "imap.zoho." + region
    region = "com"
    for suffix in ("zoho.com.au", "zoho.eu", "zoho.in"):
        if mx_host.endswith(suffix):
            region = suffix[5:]
    return "imappro.zoho." + region


def provider_for_host(host):
    for provider, info in PROVIDERS.items():
        if info["host"] and info["host"] == host and provider != "proton":
            return provider
    if host.endswith(".gmail.com") or host.endswith(".googlemail.com"):
        return "gmail"
    if host.startswith("imap") and ".zoho." in host:
        return "zoho"
    return ""


def is_loopback(host):
    name = host.strip("[]")
    if name == "localhost":
        return True
    try:
        return ipaddress.ip_address(name).is_loopback
    except ValueError:
        return False


def parse_server(raw):
    """(host, port) from "host", "host:port", or "[v6]:port"; ("", 0) when unusable."""
    value = str(raw or "").strip().lower()
    for prefix in ("imaps://", "imap://"):
        if value.startswith(prefix):
            value = value[len(prefix):]
    value = value.rstrip("/")
    port = 993
    match = re.fullmatch(r"(\[[0-9a-f:]+\]|[^:\[\]]+)(?::(\d{1,5}))?", value)
    if not match:
        return "", 0
    host = match.group(1)
    if match.group(2):
        port = int(match.group(2))
    if not HOST.fullmatch(host) or not 0 < port < 65536:
        return "", 0
    return host, port


def resolve(address, server="", mx=None):
    """{provider, host, port} for an address, or MailError with what to do."""
    domain = domain_of(address)
    if server:
        host, port = parse_server(server)
        if not host:
            raise MailError("error", "That server isn't a host name, like imap.%s" % domain)
        if host.endswith(".office365.com") or host.endswith(".outlook.com"):
            raise MailError("error", REFUSED["microsoft"])
        provider = provider_for_host(host) or provider_for_domain(domain)
        if provider in REFUSED or (provider == "proton" and not is_loopback(host)):
            provider = "other"
        return {"provider": provider or "other", "host": host, "port": port}
    provider = provider_for_domain(domain)
    mx_host = ""
    if not provider:
        provider, mx_host = provider_for_mx((mx or lookup_mx)(domain))
    if provider in REFUSED:
        raise MailError("error", REFUSED[provider])
    if not provider:
        raise MailError("error", "Couldn't tell which server %s uses. Type its IMAP server, like imap.%s" % (domain, domain))
    info = PROVIDERS[provider]
    host = zoho_host(domain, mx_host) if provider == "zoho" else info["host"]
    return {"provider": provider, "host": host, "port": info["port"]}


def login_names(address, provider):
    """Who to sign in as. iCloud wants the name before the @ for its own
    addresses, and says to try the whole address when that fails."""
    local, domain = address.rsplit("@", 1)
    if provider == "icloud" and domain in ("icloud.com", "me.com", "mac.com"):
        return [local, address]
    return [address]


def web_link(account):
    info = PROVIDERS.get(account.get("provider"), PROVIDERS["other"])
    return info["web"].replace("{address}", quote(account.get("address", ""), safe=""))


def message_link(account, thread_id):
    """The conversation on mail.google.com, for an account on a Gmail server."""
    if not account.get("gmail") or not thread_id:
        return ""
    try:
        hexid = format(int(thread_id), "x")
    except ValueError:
        return ""
    return "https://mail.google.com/mail/u/?authuser=%s#inbox/%s" % (quote(account.get("address", ""), safe=""), hexid)


# —— DNS, for a custom domain's MX ——


def resolvers(path="/etc/resolv.conf"):
    out = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                parts = line.split()
                if len(parts) > 1 and parts[0] == "nameserver":
                    out.append(parts[1].split("%", 1)[0])
    except OSError:
        pass
    return out


def dns_query(name, ident, qtype=15):
    labels = [label for label in name.encode("idna").split(b".") if label]
    question = b"".join(bytes([len(label)]) + label for label in labels) + b"\0"
    return struct.pack(">HHHHHH", ident, 0x0100, 1, 0, 0, 0) + question + struct.pack(">HH", qtype, 1)


def read_name(packet, offset):
    """(name, offset after it), following compression pointers."""
    labels = []
    end = None
    for _ in range(64):
        length = packet[offset]
        if length & 0xC0 == 0xC0:
            if end is None:
                end = offset + 2
            offset = ((length & 0x3F) << 8) | packet[offset + 1]
            continue
        if length == 0:
            return ".".join(labels), (end if end is not None else offset + 1)
        labels.append(packet[offset + 1:offset + 1 + length].decode("ascii", "replace"))
        offset += 1 + length
    raise ValueError("DNS name loops")


def parse_mx(packet, ident):
    """MX hosts in preference order, from a DNS reply."""
    got, flags, questions, answers, _, _ = struct.unpack(">HHHHHH", packet[:12])
    if got != ident or flags & 0x000F:
        return []
    offset = 12
    for _ in range(questions):
        _, offset = read_name(packet, offset)
        offset += 4
    found = []
    for _ in range(answers):
        _, offset = read_name(packet, offset)
        rtype, _, _, length = struct.unpack(">HHIH", packet[offset:offset + 10])
        offset += 10
        if rtype == 15:
            preference = struct.unpack(">H", packet[offset:offset + 2])[0]
            host, _ = read_name(packet, offset + 2)
            found.append((preference, host.lower().rstrip(".")))
        offset += length
    return [host for _, host in sorted(found)]


def lookup_mx(domain, servers=None, timeout=DNS_TIMEOUT):
    """Ask this machine's own resolver, so the domain goes nowhere new."""
    for server in (servers if servers is not None else resolvers()):
        ident = random.randrange(1, 0xFFFF)
        family = socket.AF_INET6 if ":" in server else socket.AF_INET
        try:
            with socket.socket(family, socket.SOCK_DGRAM) as sock:
                sock.settimeout(timeout)
                sock.sendto(dns_query(domain, ident), (server, 53))
                reply = sock.recv(4096)
            return parse_mx(reply, ident)
        except (OSError, ValueError, IndexError, struct.error, UnicodeError):
            continue
    return []


# —— IMAP ——


def connect(host, port, timeout=TIMEOUT):
    """A connection that is encrypted before any password goes over it."""
    loopback = is_loopback(host)
    context = ssl.create_default_context()
    if loopback:
        # Proton Mail Bridge's certificate is its own, and the traffic never
        # leaves this machine.
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    name = host.strip("[]")
    try:
        if port == 993:
            return imaplib.IMAP4_SSL(name, port, ssl_context=context, timeout=timeout)
        conn = imaplib.IMAP4(name, port, timeout=timeout)
        if "STARTTLS" in conn.capabilities:
            conn.starttls(ssl_context=context)
        elif not loopback:
            conn.shutdown()
            raise MailError("tls", "%s offers no encrypted connection on port %d" % (host, port))
        return conn
    except ssl.SSLCertVerificationError:
        raise MailError("tls", "%s's certificate isn't valid" % host)
    except ConnectionRefusedError:
        if loopback and port == 1143:
            raise MailError("offline", "Proton Mail Bridge isn't running")
        raise MailError("offline", "%s refused the connection" % host)
    except socket.gaierror:
        raise MailError("offline", "Can't reach %s" % host)
    except (TimeoutError, socket.timeout):
        raise MailError("offline", "%s didn't answer" % host)
    except (imaplib.IMAP4.error, ssl.SSLError) as error:
        raise MailError("error", "%s: %s" % (host, server_text(error)))
    except OSError:
        raise MailError("offline", "Can't reach %s" % host)


def server_text(error):
    value = error.args[0] if getattr(error, "args", None) else error
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    return one_line(value, 200)


def login_failure(text):
    """What a refused sign-in means, in the user's terms."""
    lower = text.lower()
    if "application-specific password" in lower or "app password" in lower:
        return "Use an app password, not the account's own password"
    if "not enabled for imap" in lower or "imap access is disabled" in lower or "imap is disabled" in lower:
        return "IMAP is turned off for this account"
    if "web browser" in lower or "webalert" in lower or "web login" in lower:
        return "Sign in once on the web, then try again"
    if "too many" in lower or "rate" in lower and "limit" in lower or "throttl" in lower:
        return "Too many sign-ins. Try again in a few minutes"
    if "invalid credentials" in lower or "authenticationfailed" in lower or "authentication failed" in lower or "login failed" in lower:
        return "Wrong address or app password"
    return text or "The server refused the sign-in"


def sign_in(conn, user, password):
    """AUTHENTICATE PLAIN where the server offers it, which every big provider
    does and which carries any UTF-8 password; LOGIN otherwise."""
    try:
        if "AUTH=PLAIN" in (c.upper() for c in conn.capabilities):
            secret = ("\0%s\0%s" % (user, password)).encode("utf-8")
            conn.authenticate("PLAIN", lambda _challenge: secret)
        else:
            conn.login(user, password)
    except imaplib.IMAP4.abort:
        raise MailError("offline", "The server hung up during the sign-in")
    except imaplib.IMAP4.error as error:
        raise MailError("auth", login_failure(server_text(error)))
    except UnicodeError:
        raise MailError("auth", "The server only takes plain ASCII passwords")
    except OSError:
        raise MailError("offline", "The server stopped answering during the sign-in")


def capabilities(conn):
    try:
        status, data = conn.capability()
    except imaplib.IMAP4.error:
        return set(c.upper() for c in conn.capabilities)
    words = b" ".join(d for d in data if isinstance(d, bytes)).decode("ascii", "replace").upper().split()
    return set(words) | set(c.upper() for c in conn.capabilities)


def open_inbox(conn, readonly=True):
    """The inbox's UIDVALIDITY. EXAMINE when only reading, so nothing changes."""
    try:
        status, data = conn.select("INBOX", readonly=readonly)
    except imaplib.IMAP4.error as error:
        raise MailError("error", "The inbox didn't open: %s" % server_text(error))
    if status != "OK":
        raise MailError("error", "The inbox didn't open")
    _, values = conn.response("UIDVALIDITY")
    try:
        return int(values[-1])
    except (TypeError, ValueError, IndexError):
        return 0


def gm_quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unread_uids(conn, gmail, view):
    if gmail and view in GMAIL_QUERIES:
        status, data = conn.uid("SEARCH", "X-GM-RAW", gm_quote(GMAIL_QUERIES[view]))
    else:
        status, data = conn.uid("SEARCH", "UNSEEN")
    if status != "OK":
        raise MailError("error", "The server couldn't search the inbox")
    words = b" ".join(d for d in data if isinstance(d, bytes)).split()
    return sorted(int(w) for w in words if w.isdigit())


# —— Reading FETCH replies ——


def responses(data):
    """imaplib's FETCH data, one list of chunks per message. A tuple is a line
    that ends in a literal plus that literal; a bare line ends the message."""
    out, current = [], []
    for item in data or []:
        if isinstance(item, tuple) and len(item) == 2:
            current.append(("text", item[0]))
            current.append(("literal", item[1]))
        elif isinstance(item, bytes):
            current.append(("text", item))
            out.append(current)
            current = []
    if current:
        out.append(current)
    return out


def tokens(chunks):
    out = []
    for kind, value in chunks:
        if kind == "literal":
            out.append(("value", value))
            continue
        text = value or b""
        i = 0
        while i < len(text):
            ch = text[i:i + 1]
            if ch in b" \r\n\t":
                i += 1
            elif ch == b"(":
                out.append(("open", None))
                i += 1
            elif ch == b")":
                out.append(("close", None))
                i += 1
            elif ch == b'"':
                j = i + 1
                buf = bytearray()
                while j < len(text) and text[j:j + 1] != b'"':
                    if text[j:j + 1] == b"\\" and j + 1 < len(text):
                        j += 1
                    buf += text[j:j + 1]
                    j += 1
                out.append(("value", bytes(buf)))
                i = j + 1
            elif ch == b"{":
                # The literal's size: its bytes are the next chunk.
                end = text.find(b"}", i)
                i = len(text) if end < 0 else end + 1
            else:
                j = i
                depth = 0
                while j < len(text):
                    c = text[j:j + 1]
                    if c == b"[":
                        depth += 1
                    elif c == b"]":
                        depth = max(0, depth - 1)
                    elif depth == 0 and c in b" ()\r\n":
                        break
                    j += 1
                atom = text[i:j].decode("utf-8", "replace")
                out.append(("value", None if atom.upper() == "NIL" else atom))
                i = j
    return out


def nest(items):
    stack = [[]]
    for kind, value in items:
        if kind == "open":
            stack.append([])
        elif kind == "close":
            if len(stack) > 1:
                done = stack.pop()
                stack[-1].append(done)
        else:
            stack[-1].append(value)
    while len(stack) > 1:
        done = stack.pop()
        stack[-1].append(done)
    return stack[0]


def fetch_items(chunks):
    """{ITEM: value} for one message's FETCH response."""
    tree = nest(tokens(chunks))
    body = next((part for part in tree if isinstance(part, list)), None)
    if body is None:
        return {}
    out = {}
    for i in range(0, len(body) - 1, 2):
        key = body[i]
        if isinstance(key, str):
            key = key.upper()
            out["BODY[HEADER]" if key.startswith("BODY[") else key] = body[i + 1]
    return out


def as_text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return "" if value is None else str(value)


def internal_date(value):
    """Epoch seconds from INTERNALDATE, like "02-Oct-2026 08:15:00 -0600"."""
    match = re.fullmatch(r"\s*(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})", as_text(value))
    if not match or match.group(2).lower() not in MONTHS:
        return None
    day, month, year, hour, minute, second, sign, oh, om = match.groups()
    offset = timedelta(hours=int(oh), minutes=int(om)) * (-1 if sign == "-" else 1)
    when = datetime(int(year), MONTHS[month.lower()], int(day), int(hour), int(minute), int(second), tzinfo=timezone(offset))
    return int(when.timestamp())


def decoded(raw):
    """An RFC 2047 header as text, as well as a mangled one allows. Raw 8-bit
    text in a header, which plenty of senders write, has no charset to go by,
    so it is read as UTF-8, then Latin-1."""
    try:
        parts = decode_header(raw)
    except Exception:
        parts = [(str(raw), None)]
    out = []
    for value, charset in parts:
        if isinstance(value, bytes):
            text = None
            for name in (str(charset or ""), "utf-8", "latin-1"):
                if not name or name.lower() == "unknown-8bit":
                    continue
                try:
                    text = value.decode(name)
                    break
                except (LookupError, UnicodeDecodeError):
                    continue
            value = text if text is not None else value.decode("utf-8", "replace")
        out.append(value)
    return "".join(out).encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def header_fields(raw):
    """(sender name, sender address, subject, date) from a header block. Each
    field is read on its own, so one mangled header loses only itself."""
    raw = raw if isinstance(raw, bytes) else as_text(raw).encode("utf-8")
    msg = BytesHeaderParser(policy=policy.compat32).parsebytes(raw)
    subject = decoded(msg.get("Subject") or "")
    name, address = email.utils.parseaddr(decoded(msg.get("From") or ""))
    sent = None
    try:
        sent = int(email.utils.parsedate_to_datetime(str(msg.get("Date") or "")).timestamp())
    except (TypeError, ValueError, OverflowError):
        pass
    name = one_line(name.strip('"\''), 80)
    address = one_line(address, 120)
    if not name:
        name = address.split("@", 1)[0] if address else "Unknown sender"
    return name, address, one_line(subject, 200), sent


def message_of(items, account):
    try:
        uid = int(as_text(items.get("UID")))
    except ValueError:
        return None
    flags = [as_text(f).lower() for f in items.get("FLAGS") or [] if f is not None]
    labels = [as_text(l).lower() for l in items.get("X-GM-LABELS") or [] if l is not None]
    name, address, subject, sent = header_fields(items.get("BODY[HEADER]") or b"")
    return {
        "uid": uid,
        "from": name,
        "address": address,
        "subject": subject or "(no subject)",
        "date": internal_date(items.get("INTERNALDATE")) or sent or 0,
        "flagged": "\\flagged" in flags,
        "important": "\\important" in labels,
        "link": message_link(account, as_text(items.get("X-GM-THRID"))),
    }


def fetch_messages(conn, uids, account, gmail):
    if not uids:
        return []
    items = ["UID", "FLAGS", "INTERNALDATE"] + (["X-GM-THRID", "X-GM-LABELS"] if gmail else []) + [HEADER_ITEM]
    status, data = conn.uid("FETCH", ",".join(str(u) for u in uids), "(" + " ".join(items) + ")")
    if status != "OK":
        raise MailError("error", "The server couldn't read the messages")
    out = []
    for chunks in responses(data):
        message = message_of(fetch_items(chunks), account)
        if message and message["uid"] in uids:
            out.append(message)
    out.sort(key=lambda m: (m["date"], m["uid"]), reverse=True)
    return out


def close(conn):
    try:
        conn.logout()
    except Exception:
        try:
            conn.shutdown()
        except Exception:
            pass


def session(account, connector=connect):
    """A signed-in connection, or MailError."""
    conn = connector(account["host"], int(account.get("port") or 993))
    try:
        sign_in(conn, account.get("user") or account["address"], account["password"])
    except BaseException:
        close(conn)
        raise
    return conn


def read_account(account, connector=connect, limit=PER_ACCOUNT):
    """The account's unread count and its newest unread messages."""
    conn = session(account, connector)
    try:
        gmail = "X-GM-EXT-1" in capabilities(conn)
        uidvalidity = open_inbox(conn)
        uids = unread_uids(conn, gmail, account.get("view") or "inbox")
        newest = uids[-limit:] if limit else []
        live = dict(account, gmail=gmail)
        messages = fetch_messages(conn, newest, live, gmail)
        return {"unread": len(uids), "uidvalidity": uidvalidity, "gmail": gmail, "messages": messages}
    except (imaplib.IMAP4.abort, OSError) as error:
        raise MailError("offline", "%s stopped answering" % account["host"]) from error
    except imaplib.IMAP4.error as error:
        raise MailError("error", server_text(error))
    finally:
        close(conn)


# —— Saved accounts ——


def config_path():
    root = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(root, "ande.launcher", "mail-accounts.json")


def cache_path():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(root, "ande.launcher", "mail.json")


def read_saved(path=None):
    try:
        with open(path or config_path(), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return []
    rows = data.get("accounts") if isinstance(data, dict) else None
    if not isinstance(rows, list):
        return []
    return [r for r in rows if isinstance(r, dict) and r.get("id") and r.get("address") and r.get("password") and r.get("host")]


def write_private(path, payload):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def write_saved(rows, path=None):
    write_private(path or config_path(), {"accounts": rows})


def public(account):
    """An account as the panel and the tile see it: never the password."""
    provider = account.get("provider") or "other"
    return {
        "id": account["id"],
        "name": account.get("name") or account["address"],
        "address": account["address"],
        "provider": provider,
        "providerName": PROVIDERS.get(provider, PROVIDERS["other"])["name"],
        "where": account["host"] + ("" if int(account.get("port") or 993) == 993 else ":%d" % int(account["port"])),
        "gmail": bool(account.get("gmail")),
        "view": account.get("view") or "inbox",
        "web": web_link(account),
    }


# —— The tile ——


def read_cache(path=None):
    try:
        with open(path or cache_path(), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def collect(saved=None, connector=connect, cache=None, now=None):
    now = time.time() if now is None else now
    saved = read_saved() if saved is None else saved
    accounts = saved[:MAX_ACCOUNTS]
    old = {a.get("id"): a for a in (read_cache(cache).get("accounts") or []) if isinstance(a, dict)}

    def one(account):
        row = dict(public(account), ok=True, state="ok", error="", unread=0, uidvalidity=0, messages=[], at=int(now), stale=False)
        try:
            row.update(read_account(account, connector))
        except MailError as error:
            row.update(ok=False, state=error.state, error=error.message)
        except Exception as error:
            row.update(ok=False, state="error", error=one_line(error, 160) or "The account didn't answer")
        if not row["ok"]:
            last = old.get(account["id"])
            usable = last and (last.get("ok") or last.get("stale"))
            if usable and 0 <= now - float(last.get("at") or 0) < STALE_MAX:
                row.update(unread=last.get("unread") or 0, uidvalidity=last.get("uidvalidity") or 0,
                           messages=last.get("messages") or [], at=last.get("at"), stale=True)
        return row

    rows = []
    if accounts:
        with ThreadPoolExecutor(max_workers=len(accounts)) as pool:
            rows = list(pool.map(one, accounts))
    return {"ok": True, "accounts": rows, "unread": sum(int(r["unread"] or 0) for r in rows), "savedAt": int(now * 1000)}


def write_cache(payload, path=None):
    """Keep the last reply, for an instant draw and for an account that stops
    answering. A stale account keeps the time of the copy it stands in for,
    so it still runs out a day after that copy was read."""
    keep = dict(payload, accounts=[a for a in payload.get("accounts") or [] if a.get("ok") or a.get("stale")])
    if not keep["accounts"]:
        return
    try:
        write_private(path or cache_path(), keep)
    except OSError:
        pass


# —— The panel ——


def listing(saved=None):
    saved = read_saved() if saved is None else saved
    return {"ok": True, "accounts": [public(a) for a in saved], "max": MAX_ACCOUNTS}


def add(address, password, server="", path=None, connector=connect, mx=None):
    address = clean_address(address)
    if not address:
        return {"ok": False, "error": "That isn't an email address"}
    password = clean_password(password)
    if not password:
        return {"ok": False, "error": "Paste the app password too"}
    saved = read_saved(path)
    if len(saved) >= MAX_ACCOUNTS:
        return {"ok": False, "error": "Up to %d accounts" % MAX_ACCOUNTS}
    if any(a["address"].lower() == address.lower() for a in saved):
        return {"ok": False, "error": "That account is already on the tile"}
    try:
        place = resolve(address, server, mx)
    except MailError as error:
        return {"ok": False, "error": error.message}
    gmail_address = domain_of(address) in ("gmail.com", "googlemail.com")
    account = {
        "id": secrets.token_hex(6),
        "address": address,
        "user": address,
        "password": password,
        "host": place["host"],
        "port": place["port"],
        "provider": place["provider"],
        "view": "primary" if gmail_address else "inbox",
    }
    names = login_names(address, place["provider"])
    result = None
    for index, user in enumerate(names):
        try:
            result = read_account(dict(account, user=user), connector, limit=0)
            account["user"] = user
            break
        except MailError as error:
            if error.state == "auth" and index + 1 < len(names):
                continue
            hint = error.message
            if error.state == "auth" and place["provider"] == "proton":
                hint += " (use the password Proton Mail Bridge shows, not your Proton password)"
            return {"ok": False, "error": hint}
    account["gmail"] = bool(result and result["gmail"])
    if not account["gmail"]:
        account["view"] = "inbox"
    if account["gmail"] and account["provider"] == "other":
        account["provider"] = "gmail"
    write_saved(saved + [account], path)
    return {"ok": True, "account": public(account), "unread": result["unread"] if result else 0}


def remove(account_id, path=None):
    saved = read_saved(path)
    keep = [a for a in saved if a["id"] != account_id]
    if len(keep) == len(saved):
        return {"ok": False}
    write_saved(keep, path)
    return {"ok": True}


def set_view(account_id, view, path=None):
    if view not in VIEWS:
        return {"ok": False, "error": "Unknown view"}
    saved = read_saved(path)
    for account in saved:
        if account["id"] == account_id:
            if not account.get("gmail") and view != "inbox":
                return {"ok": False, "error": "Only Gmail has tabs"}
            account["view"] = view
            write_saved(saved, path)
            return {"ok": True, "account": public(account)}
    return {"ok": False, "error": "No such account"}


def mark_read(account_id, uidvalidity, uid, path=None, connector=connect):
    if not str(uidvalidity).isdigit() or not str(uid).isdigit():
        return {"ok": False, "error": "Not a message"}
    account = next((a for a in read_saved(path) if a["id"] == account_id), None)
    if not account:
        return {"ok": False, "error": "No such account"}
    try:
        conn = session(account, connector)
    except MailError as error:
        return {"ok": False, "error": error.message}
    try:
        if open_inbox(conn, readonly=False) != int(uidvalidity):
            return {"ok": False, "error": "The inbox changed. It will refresh"}
        status, _ = conn.uid("STORE", str(int(uid)), "+FLAGS.SILENT", "(\\Seen)")
        return {"ok": status == "OK"}
    except (MailError, imaplib.IMAP4.error, OSError) as error:
        return {"ok": False, "error": getattr(error, "message", None) or server_text(error)}
    finally:
        close(conn)


def main(argv):
    args = argv[1:]

    def arg(flag, n=1):
        index = args.index(flag)
        values = args[index + 1:index + 1 + n]
        return values + [""] * (n - len(values))

    if "--list" in args:
        payload = listing()
    elif "--add" in args:
        payload = add(os.environ.get(ADDRESS_ENV, ""), os.environ.get(PASSWORD_ENV, ""), os.environ.get(SERVER_ENV, ""))
    elif "--remove" in args:
        payload = remove(arg("--remove")[0])
    elif "--view" in args:
        payload = set_view(*arg("--view", 2))
    elif "--read" in args:
        payload = mark_read(*arg("--read", 3))
    else:
        payload = collect()
        write_cache(payload)
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
