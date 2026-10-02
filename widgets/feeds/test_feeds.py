#!/usr/bin/env python3
"""Tests for the feeds sampler. Stdlib only; nothing here reaches the network.

Run from the repo root:  python3 widgets/feeds/test_feeds.py
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import feeds

RSS = b"""<?xml version="1.0"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
  <title>Example &amp; Co</title>
  <item><title>First &lt;b&gt;bold&lt;/b&gt; story</title><link>https://example.com/1</link>
        <pubDate>Thu, 01 Oct 2026 20:00:00 +0000</pubDate></item>
  <item><title>Second</title><guid isPermaLink="true">https://example.com/2</guid>
        <dc:date>2026-10-01T18:00:00Z</dc:date></item>
  <item><title>No permalink</title><guid isPermaLink="false">abc-123</guid></item>
  <item><title>   </title><link>https://example.com/empty</link></item>
  <item><title>Bad link</title><link>javascript:alert(1)</link></item>
</channel></rss>"""

ATOM = b"""<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title type="html">Releases</title>
  <entry><title>v4.0.1</title><link rel="alternate" href="/basecamp/omarchy/releases/tag/v4.0.1"/>
         <updated>2026-10-01T12:00:00Z</updated></entry>
  <entry><title>v4.0.0</title><link rel="enclosure" href="https://x/file.zip"/><link href="https://github.com/r/v4"/>
         <published>2026-09-30T12:00:00+02:00</published><updated>2026-10-01T00:00:00Z</updated></entry>
</feed>"""

RDF = b"""<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel><title>Old School</title></channel>
  <item><title>One</title><link>https://old.example/1</link><dc:date>2026-09-01T00:00:00Z</dc:date></item>
</rdf:RDF>"""

PAGE = b"""<html><head>
<link rel="stylesheet" href="/s.css">
<link rel="alternate" type="application/rss+xml" title="Feed" href="/feed.xml?a=1&amp;b=2">
</head></html>"""


def fetcher_for(routes):
    def fetch(url, timeout=None):
        answer = routes.get(url)
        if answer is None:
            raise feeds.FeedError("did not answer")
        if isinstance(answer, Exception):
            raise answer
        return answer
    return fetch


class ParseTests(unittest.TestCase):
    def test_rss(self):
        title, items = feeds.parse_feed(RSS, "https://example.com/rss")
        self.assertEqual(title, "Example & Co")
        self.assertEqual([i["title"] for i in items], ["First bold story", "Second", "No permalink", "Bad link"])
        self.assertEqual(items[0]["link"], "https://example.com/1")
        self.assertEqual(items[0]["at"], 1790884800)
        self.assertEqual(items[1]["link"], "https://example.com/2")
        self.assertEqual(items[1]["at"], 1790877600)
        self.assertEqual(items[2]["link"], "")
        self.assertIsNone(items[2]["at"])
        self.assertEqual(items[3]["link"], "")

    def test_atom_prefers_alternate_and_published(self):
        title, items = feeds.parse_feed(ATOM, "https://github.com/basecamp/omarchy/releases.atom")
        self.assertEqual(title, "Releases")
        self.assertEqual(items[0]["link"], "https://github.com/basecamp/omarchy/releases/tag/v4.0.1")
        self.assertEqual(items[1]["link"], "https://github.com/r/v4")
        self.assertEqual(items[1]["at"], 1790762400)

    def test_rdf(self):
        title, items = feeds.parse_feed(RDF)
        self.assertEqual(title, "Old School")
        self.assertEqual(items[0]["link"], "https://old.example/1")

    def test_not_a_feed(self):
        for body in (b"<html><body>hi</body></html>", b"not xml", b"{}"):
            with self.assertRaises(feeds.FeedError):
                feeds.parse_feed(body)

    def test_caps_items_per_feed(self):
        body = b"<rss><channel><title>t</title>" + b"".join(b"<item><title>n%d</title></item>" % i for i in range(40)) + b"</channel></rss>"
        self.assertEqual(len(feeds.parse_feed(body)[1]), feeds.PER_FEED)

    def test_clean_text(self):
        self.assertEqual(feeds.clean_text("A &amp;amp; B"), "A & B")
        self.assertEqual(feeds.clean_text("<p>Hello\n  <i>world</i></p>"), "Hello world")
        self.assertEqual(len(feeds.clean_text("x" * 500)), 200)

    def test_dates(self):
        self.assertEqual(feeds.parse_date("Thu, 01 Oct 2026 20:00:00 GMT"), 1790884800)
        self.assertEqual(feeds.parse_date("2026-10-01T20:00:00Z"), 1790884800)
        self.assertEqual(feeds.parse_date("2026-10-01T22:00:00+02:00"), 1790884800)
        self.assertEqual(feeds.parse_date("2026-10-01"), 1790812800)
        self.assertIsNone(feeds.parse_date("yesterday"))
        self.assertIsNone(feeds.parse_date(""))

    def test_discover(self):
        self.assertEqual(feeds.discover(PAGE, "https://site.example/blog/"), "https://site.example/feed.xml?a=1&b=2")
        self.assertEqual(feeds.discover(b"<html></html>", "https://x/"), "")


class UrlTests(unittest.TestCase):
    def test_clean_url(self):
        self.assertEqual(feeds.clean_url("xkcd.com"), "https://xkcd.com")
        self.assertEqual(feeds.clean_url("http://a.example/rss?x=1"), "http://a.example/rss?x=1")
        for bad in ("", "file:///etc/passwd", "javascript:x", "https://u@x.org", "https://x.org/a b"):
            self.assertEqual(feeds.clean_url(bad), "", bad)

    def test_clean_link(self):
        self.assertEqual(feeds.clean_link("/a", "https://x.org/b/"), "https://x.org/a")
        self.assertEqual(feeds.clean_link("data:text/html,x", "https://x.org/"), "")
        self.assertEqual(feeds.clean_link("https://x.org/\"onmouseover"), "")

    def test_clean_feeds(self):
        rows = feeds.clean_feeds(json.dumps(["hn", "hn", "nope", {"url": "xkcd.com/atom.xml"}, {"url": "https://news.ycombinator.com/rss"}]))
        self.assertEqual([r["key"] for r in rows], ["hn", "https://xkcd.com/atom.xml"])
        self.assertEqual(rows[1]["name"], "xkcd.com")
        self.assertEqual([r["key"] for r in feeds.clean_feeds(None)], feeds.DEFAULTS)
        self.assertEqual(len(feeds.clean_feeds(list(feeds.CATALOG))), feeds.MAX_FEEDS)


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.folder = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def test_merges_newest_first_and_dates_undated_items(self):
        fetch = fetcher_for({"https://a.example/rss": RSS, "https://b.example/atom": ATOM})
        now = 1790900000
        out = feeds.collect([{"url": "a.example/rss", "name": "A"}, {"url": "b.example/atom", "name": "B"}], now, fetch, self.folder)
        titles = [i["title"] for i in out["items"]]
        self.assertEqual(titles[:2], ["No permalink", "Bad link"])
        self.assertEqual(titles[2:5], ["First bold story", "Second", "v4.0.1"])
        self.assertEqual(out["items"][2]["source"], "A")
        self.assertTrue(all(f["ok"] for f in out["feeds"]))

    def test_cache_is_used_while_young(self):
        calls = []

        def fetch(url, timeout=None):
            calls.append(url)
            return RSS

        feed = {"key": "x", "name": "X", "url": "https://x.example/rss"}
        feeds.load_feed(feed, 1000, fetch, self.folder)
        feeds.load_feed(feed, 1000 + feeds.TTL - 1, fetch, self.folder)
        self.assertEqual(len(calls), 1)
        feeds.load_feed(feed, 1000 + feeds.TTL + 1, fetch, self.folder)
        self.assertEqual(len(calls), 2)
        feeds.load_feed(feed, 1000 + feeds.TTL + 2, fetch, self.folder, fresh=True)
        self.assertEqual(len(calls), 3)

    def test_stale_copy_stands_in_for_a_dead_feed(self):
        feed = {"key": "x", "name": "X", "url": "https://x.example/rss"}
        feeds.load_feed(feed, 1000, fetcher_for({feed["url"]: RSS}), self.folder)
        data = feeds.load_feed(feed, 1000 + feeds.TTL + 5, fetcher_for({}), self.folder)
        self.assertEqual(data["error"], "did not answer")
        self.assertEqual(len(data["items"]), 4)
        gone = feeds.load_feed(feed, 1000 + feeds.STALE_MAX + 5, fetcher_for({}), self.folder)
        self.assertEqual(gone["items"], [])

    def test_a_failing_feed_is_reported(self):
        out = feeds.collect([{"url": "dead.example"}], 0, fetcher_for({}), self.folder)
        self.assertEqual(out["feeds"][0], {"key": "https://dead.example", "name": "dead.example", "ok": False, "error": "did not answer"})


class ProbeTests(unittest.TestCase):
    def test_direct_feed(self):
        out = feeds.probe("a.example/rss", fetcher_for({"https://a.example/rss": RSS}))
        self.assertEqual(out, {"ok": True, "url": "https://a.example/rss", "name": "Example & Co", "count": 4})

    def test_page_that_links_a_feed(self):
        fetch = fetcher_for({"https://site.example": PAGE, "https://site.example/feed.xml?a=1&b=2": ATOM})
        out = feeds.probe("site.example", fetch)
        self.assertEqual((out["ok"], out["url"], out["name"]), (True, "https://site.example/feed.xml?a=1&b=2", "Releases"))

    def test_errors(self):
        self.assertEqual(feeds.probe("site.example", fetcher_for({"https://site.example": b"<html></html>"}))["error"], "No feed at site.example")
        self.assertEqual(feeds.probe("gone.example", fetcher_for({}))["error"], "gone.example did not answer")
        self.assertEqual(feeds.probe("javascript:alert(1)", fetcher_for({}))["error"], "That isn't a web address")


class CatalogTests(unittest.TestCase):
    def test_catalog(self):
        for key, (name, url) in feeds.CATALOG.items():
            self.assertTrue(name)
            self.assertEqual(feeds.clean_url(url), url, key)
        for key in feeds.DEFAULTS:
            self.assertIn(key, feeds.CATALOG)


if __name__ == "__main__":
    unittest.main()
