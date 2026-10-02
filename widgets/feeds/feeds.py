#!/usr/bin/env python3
"""Headlines from RSS and Atom feeds, for the launcher tile. Stdlib only.

    feeds.py --feeds JSON    the tile: the newest headlines across the feeds
    feeds.py --probe URL     the settings panel: the feed at a URL, or the one
                             a web page links to
    feeds.py --catalog       the settings panel: the feeds it suggests

A feed is a catalog id ("hn") or {"url": "https://...", "name": "..."}.
RSS 2.0, RSS 1.0 (RDF) and Atom are read; titles lose their markup and
entities. Each feed is cached for fifteen minutes, and an old copy stands in
when the feed does not answer, so one dead feed never blanks the tile.
"""

import hashlib
import html
import json
import os
import re
import sys
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) omarchy-launcher-feeds"
TIMEOUT = 10
MAX_BODY = 6_000_000
MAX_FEEDS = 6
PER_FEED = 15
MAX_ITEMS = 40
TTL = 15 * 60
STALE_MAX = 7 * 86400

# id: (name, url). Checked live on 2026-10-02.
CATALOG = {
    "hn": ("Hacker News", "https://news.ycombinator.com/rss"),
    "lobsters": ("Lobsters", "https://lobste.rs/rss"),
    "arch": ("Arch Linux news", "https://archlinux.org/feeds/news/"),
    "omarchy": ("Omarchy releases", "https://github.com/basecamp/omarchy/releases.atom"),
    "hyprland": ("Hyprland releases", "https://github.com/hyprwm/Hyprland/releases.atom"),
    "phoronix": ("Phoronix", "https://www.phoronix.com/rss.php"),
    "lwn": ("LWN.net", "https://lwn.net/headlines/rss"),
    "9to5linux": ("9to5Linux", "https://9to5linux.com/feed/"),
    "rlinux": ("r/linux", "https://www.reddit.com/r/linux/.rss"),
    "verge": ("The Verge", "https://www.theverge.com/rss/index.xml"),
    "ars": ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index"),
    "wired": ("Wired", "https://www.wired.com/feed/rss"),
    "techcrunch": ("TechCrunch", "https://techcrunch.com/feed/"),
    "404media": ("404 Media", "https://www.404media.co/rss/"),
    "simonw": ("Simon Willison", "https://simonwillison.net/atom/everything/"),
    "openai": ("OpenAI News", "https://openai.com/news/rss.xml"),
    "rust": ("Rust Blog", "https://blog.rust-lang.org/feed.xml"),
    "go": ("The Go Blog", "https://go.dev/blog/feed.atom"),
    "krebs": ("Krebs on Security", "https://krebsonsecurity.com/feed/"),
    "bleeping": ("BleepingComputer", "https://www.bleepingcomputer.com/feed/"),
    "thn": ("The Hacker News", "https://feeds.feedburner.com/TheHackersNews"),
    "bbc": ("BBC News", "https://feeds.bbci.co.uk/news/rss.xml"),
    "npr": ("NPR News", "https://feeds.npr.org/1001/rss.xml"),
    "nyt": ("New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"),
    "guardian": ("The Guardian", "https://www.theguardian.com/world/rss"),
}
DEFAULTS = ["hn", "lobsters", "arch"]

HOST = re.compile(r"[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*(:\d{1,5})?")
TAG = re.compile(r"<[^>]+>")


class FeedError(Exception):
    pass


def fetch(url, timeout=TIMEOUT):
    """The body of a GET, or FeedError."""
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8, */*;q=0.5"})
    try:
        with urlopen(request, timeout=timeout) as reply:
            return reply.read(MAX_BODY)
    except HTTPError as error:
        raise FeedError("answered %d" % error.code)
    except (URLError, OSError, ValueError):
        raise FeedError("did not answer")


def clean_text(value, limit=200):
    """Plain text: tags dropped, entities decoded (twice, for feeds that
    escape their HTML), whitespace folded."""
    value = html.unescape(str(value or ""))
    value = html.unescape(TAG.sub(" ", value))
    return re.sub(r"\s+", " ", value).strip()[:limit]


def clean_url(raw):
    value = str(raw or "").strip()
    if not value:
        return ""
    if "://" not in value:
        value = "https://" + value
    try:
        parts = urlsplit(value)
    except ValueError:
        return ""
    host = (parts.netloc or "").lower()
    if parts.scheme not in ("http", "https") or "@" in host or not HOST.fullmatch(host):
        return ""
    if any(ch in value for ch in " \t\n\"'<>\\`"):
        return ""
    return value[:500]


def clean_link(raw, base=""):
    """An item's link, made absolute, or "" when it is not plain http(s)."""
    value = str(raw or "").strip()
    if base and value and "://" not in value:
        value = urljoin(base, value)
    return value if re.fullmatch(r"https?://[^\s\"'<>\\`]{1,2000}", value) else ""


def parse_date(value):
    """Epoch seconds from an RFC 822 or ISO 8601 date, or None."""
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        parsed = None
    if parsed is None:
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def local(tag):
    """A tag without its namespace."""
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def child(node, *names):
    for item in node:
        if local(item.tag) in names:
            return item
    return None


def child_text(node, *names):
    found = child(node, *names)
    return "".join(found.itertext()) if found is not None else ""


def atom_link(entry):
    best = ""
    for item in entry:
        if local(item.tag) != "link":
            continue
        rel = item.get("rel") or "alternate"
        href = item.get("href") or ""
        if rel == "alternate" and href:
            return href
        best = best or href
    return best


def parse_feed(body, base=""):
    """(title, [{title, link, at}]) from RSS or Atom bytes. FeedError when it is neither."""
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        raise FeedError("is not a feed")
    kind = local(root.tag)
    items = []
    if kind == "feed":
        title = clean_text(child_text(root, "title"), 80)
        for entry in root:
            if local(entry.tag) != "entry":
                continue
            items.append({
                "title": clean_text(child_text(entry, "title")),
                "link": clean_link(atom_link(entry), base),
                "at": parse_date(child_text(entry, "published") or child_text(entry, "updated")),
            })
    elif kind in ("rss", "RDF"):
        channel = child(root, "channel")
        title = clean_text(child_text(channel, "title"), 80) if channel is not None else ""
        holder = channel if kind == "rss" and channel is not None else root
        for entry in holder:
            if local(entry.tag) != "item":
                continue
            link = child_text(entry, "link")
            if not link:
                guid = child(entry, "guid")
                if guid is not None and (guid.get("isPermaLink") or "true") != "false":
                    link = guid.text or ""
            items.append({
                "title": clean_text(child_text(entry, "title")),
                "link": clean_link(link, base),
                "at": parse_date(child_text(entry, "pubDate", "date", "published", "updated")),
            })
    else:
        raise FeedError("is not a feed")
    return title, [item for item in items if item["title"]][:PER_FEED]


def attributes(tag):
    return {name.lower(): value for name, _, value in re.findall(r'([a-zA-Z-]+)\s*=\s*(["\'])(.*?)\2', tag)}


def discover(body, base):
    """The first feed a web page links to with <link rel="alternate">."""
    text = body[:400_000].decode("utf-8", "replace")
    for tag in re.findall(r"<link\b[^>]*>", text, re.I):
        attrs = attributes(tag)
        if "alternate" not in attrs.get("rel", "").lower().split():
            continue
        if attrs.get("type", "").lower() not in ("application/rss+xml", "application/atom+xml", "application/feed+xml", "application/rdf+xml"):
            continue
        href = clean_link(html.unescape(attrs.get("href", "")), base)
        if href:
            return href
    return ""


def clean_feeds(raw):
    try:
        rows = json.loads(raw) if isinstance(raw, str) else raw
    except ValueError:
        rows = None
    if not isinstance(rows, list):
        rows = list(DEFAULTS)
    out, seen = [], set()
    for row in rows:
        if isinstance(row, str) and row in CATALOG:
            name, url = CATALOG[row]
            entry = {"key": row, "name": name, "url": url}
        elif isinstance(row, dict):
            url = clean_url(row.get("url"))
            if not url:
                continue
            entry = {"key": url, "name": clean_text(row.get("name"), 40) or urlsplit(url).netloc, "url": url}
        else:
            continue
        if entry["url"] in seen:
            continue
        seen.add(entry["url"])
        out.append(entry)
        if len(out) >= MAX_FEEDS:
            break
    return out


# —— Cache: one file per feed ——


def cache_dir():
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(root, "ande.launcher", "feeds")


def cache_file(url, folder=None):
    return os.path.join(folder or cache_dir(), hashlib.sha1(url.encode("utf-8")).hexdigest()[:20] + ".json")


def read_cached(url, folder=None):
    try:
        with open(cache_file(url, folder), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and isinstance(data.get("items"), list) else None


def write_cached(url, data, folder=None):
    path = cache_file(url, folder)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        os.replace(tmp, path)
    except OSError:
        pass


def load_feed(feed, now, fetcher=fetch, folder=None, fresh=False):
    """{title, items, at, error} for one feed, from the cache when it is young."""
    cached = read_cached(feed["url"], folder)
    if cached and not fresh and 0 <= now - float(cached.get("at") or 0) < TTL:
        return cached
    try:
        title, items = parse_feed(fetcher(feed["url"]), feed["url"])
        # An undated item keeps its place in the feed, just behind the dated ones.
        for index, item in enumerate(items):
            if item["at"] is None:
                item["at"] = int(now) - 60 - index
        data = {"title": title, "items": items, "at": now, "error": ""}
        write_cached(feed["url"], data, folder)
        return data
    except FeedError as error:
        if cached and now - float(cached.get("at") or 0) < STALE_MAX:
            return dict(cached, error=str(error))
        return {"title": "", "items": [], "at": now, "error": str(error)}


def collect(raw, now=None, fetcher=fetch, folder=None, fresh=False):
    now = time.time() if now is None else now
    feeds = clean_feeds(raw)
    if not feeds:
        return {"ok": True, "items": [], "feeds": []}
    with ThreadPoolExecutor(max_workers=len(feeds)) as pool:
        loaded = list(pool.map(lambda feed: load_feed(feed, now, fetcher, folder, fresh), feeds))
    items, status = [], []
    for feed, data in zip(feeds, loaded):
        status.append({"key": feed["key"], "name": feed["name"], "ok": not data.get("error"), "error": data.get("error") or ""})
        for item in data.get("items") or []:
            items.append({"title": item["title"], "link": item["link"], "at": item["at"], "source": feed["name"], "feed": feed["key"]})
    items.sort(key=lambda item: -(item["at"] or 0))
    return {"ok": True, "items": items[:MAX_ITEMS], "feeds": status}


def probe(raw, fetcher=fetch):
    url = clean_url(raw)
    if not url:
        return {"ok": False, "error": "That isn't a web address"}
    try:
        body = fetcher(url)
    except FeedError as error:
        return {"ok": False, "error": "%s %s" % (urlsplit(url).netloc, error)}
    try:
        title, items = parse_feed(body, url)
        return {"ok": True, "url": url, "name": title or urlsplit(url).netloc, "count": len(items)}
    except FeedError:
        pass
    found = discover(body, url)
    if not found:
        return {"ok": False, "error": "No feed at %s" % urlsplit(url).netloc}
    try:
        title, items = parse_feed(fetcher(found), found)
    except FeedError as error:
        return {"ok": False, "error": "The feed %s" % error}
    return {"ok": True, "url": found, "name": title or urlsplit(found).netloc, "count": len(items)}


def catalog():
    return [{"id": key, "name": name, "url": url} for key, (name, url) in CATALOG.items()]


def option(args, name):
    if name not in args:
        return None
    index = args.index(name)
    return args[index + 1] if index + 1 < len(args) else ""


def main(argv):
    args = argv[1:]
    if "--catalog" in args:
        payload = {"ok": True, "feeds": catalog(), "defaults": DEFAULTS}
    elif option(args, "--probe") is not None:
        payload = probe(option(args, "--probe"))
    else:
        payload = collect(option(args, "--feeds") or "null", fresh="--fresh" in args)
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
