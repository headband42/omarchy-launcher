#!/usr/bin/env node
// Logic tests for the feeds tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/feeds/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const F = require("./feeds.js");

const catalog = [
  { id: "hn", name: "Hacker News", url: "https://news.ycombinator.com/rss" },
  { id: "arch", name: "Arch Linux news", url: "https://archlinux.org/feeds/news/" },
  { id: "rlinux", name: "r/linux", url: "https://www.reddit.com/r/linux/.rss" },
];

test("ages", () => {
  assert.equal(F.fmtAge(1000, 0), "");
  assert.equal(F.fmtAge(1000, 990), "now");
  assert.equal(F.fmtAge(10000, 10000 - 300), "5m");
  assert.equal(F.fmtAge(100000, 100000 - 7200), "2h");
  assert.equal(F.fmtAge(10000000, 10000000 - 3 * 86400), "3d");
  assert.equal(F.caption({ source: "Lobsters", at: 100 }, 400), "Lobsters · 5m");
  assert.equal(F.caption({ source: "Lobsters" }, 400), "Lobsters");
});

test("new items are under an hour old", () => {
  assert.equal(F.isNew({ at: 1000 }, 1000 + 3599), true);
  assert.equal(F.isNew({ at: 1000 }, 1000 + 3600), false);
  assert.equal(F.isNew({}, 5), false);
});

test("header note", () => {
  assert.equal(F.headerNote(null), "");
  assert.equal(F.headerNote({ feeds: [{ ok: true, name: "HN" }] }), "HN");
  assert.equal(F.headerNote({ feeds: [{ ok: true }, { ok: true }] }), "2 feeds");
  assert.equal(F.headerNote({ feeds: [{ ok: true }, { ok: false }] }), "1 feed down");
});

test("settings", () => {
  assert.equal(F.feeds({}), null);
  const custom = { url: "https://xkcd.com/atom.xml", name: "xkcd" };
  assert.deepEqual(F.feeds({ feeds: ["hn", "hn", custom, { url: custom.url }, 3] }), ["hn", custom]);
  let list = F.withAdded(["hn"], custom);
  list = F.withAdded(list, custom);
  assert.deepEqual(list, ["hn", custom]);
  assert.deepEqual(F.withRemoved(list, 0), [custom]);
  assert.deepEqual(F.settingsFrom(list), { feeds: ["hn", custom] });
  const full = Array.from({ length: F.MAX_FEEDS }, (_, i) => "f" + i);
  assert.equal(F.withAdded(full, "x").length, F.MAX_FEEDS);
});

test("catalog search marks feeds already added, by id or by URL", () => {
  const hits = F.filterCatalog(catalog, "linux", ["arch", { url: "https://www.reddit.com/r/linux/.rss" }]);
  assert.deepEqual(hits.map((h) => [h.id, h.added]), [["arch", true], ["rlinux", true]]);
  assert.equal(F.filterCatalog(catalog, "ycombinator", []).length, 1);
});

test("addresses", () => {
  assert.equal(F.looksLikeUrl("xkcd.com"), true);
  assert.equal(F.looksLikeUrl("https://example.com/feed"), true);
  assert.equal(F.looksLikeUrl("hacker"), false);
  assert.equal(F.nameFor("hn", catalog), "Hacker News");
  assert.equal(F.nameFor({ url: "u", name: "N" }, catalog), "N");
});
