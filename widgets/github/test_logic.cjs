#!/usr/bin/env node
// Logic tests for the GitHub tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/github/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const G = require("./github.js");

const pr = (extra) => ({ number: 1, title: "t", url: "https://github.com/o/r/pull/1", repo: "o/r", author: "dev", draft: false, updated: 1000, checks: "", review: "", conflict: false, ...extra });

test("notes put what blocks the merge first", () => {
  assert.equal(G.note(pr({ draft: true, checks: "failure" })), "draft");
  assert.equal(G.note(pr({ conflict: true, checks: "failure" })), "conflict");
  assert.equal(G.note(pr({ checks: "failure", review: "approved" })), "checks failed");
  assert.equal(G.note(pr({ review: "changes" })), "changes requested");
  assert.equal(G.note(pr({ review: "approved", checks: "pending" })), "approved · checks running");
  assert.equal(G.note(pr({ review: "approved", checks: "success" })), "approved");
  assert.equal(G.note(pr({ checks: "pending" })), "checks running");
  assert.equal(G.note(pr({})), "");
});

test("tones only color your own pull requests", () => {
  assert.equal(G.tone(pr({ checks: "failure" }), true), "failure");
  assert.equal(G.tone(pr({ checks: "failure" }), false), "");
  assert.equal(G.tone(pr({ review: "approved", checks: "success" }), true), "success");
  assert.equal(G.tone(pr({ review: "approved", checks: "pending" }), true), "");
});

test("check glyphs", () => {
  assert.equal(G.checkGlyph(pr({ checks: "success" })), "󰄬");
  assert.equal(G.checkGlyph(pr({ checks: "failure" })), "󰅖");
  assert.equal(G.checkGlyph(pr({ checks: "pending" })), "󰔟");
  assert.equal(G.checkGlyph(pr({})), "󰘬");
});

test("captions name the author only on others' pull requests", () => {
  assert.equal(G.caption(pr({}), 1000 + 7200, false), "o/r · dev · 2h");
  assert.equal(G.caption(pr({}), 1000 + 7200, true), "o/r · 2h");
  assert.equal(G.fmtAge(1000, 990), "1m");
  assert.equal(G.fmtAge(1000 + 86400 * 3, 1000), "3d");
});

test("rows put a header before each non-empty group", () => {
  const sample = { state: "ok", reviews: { count: 5, items: [pr({ number: 1 })] }, mine: { count: 0, items: [] } };
  const rows = G.rows(sample);
  assert.deepEqual(rows.map((r) => r.kind), ["header", "pr"]);
  assert.equal(rows[0].count, 5);
  assert.equal(rows[1].mine, false);
  assert.deepEqual(G.rows({ state: "signin" }), []);
  assert.deepEqual(G.rows(null), []);
});

test("counts and empty text", () => {
  assert.equal(G.notificationsLabel({ notifications: 0 }), "");
  assert.equal(G.notificationsLabel({ notifications: 7 }), "7");
  assert.equal(G.notificationsLabel({ notifications: 50, moreNotifications: true }), "50+");
  assert.equal(G.waitingCount({ state: "ok", reviews: { count: 3 } }), 3);
  assert.equal(G.emptyText(null), "Loading…");
  assert.equal(G.emptyText({ state: "signin" }), "Run gh auth login in a terminal");
  assert.equal(G.emptyText({ state: "ok", assigned: 0 }), "Nothing waiting on you");
  assert.equal(G.emptyText({ state: "ok", assigned: 1 }), "No pull requests waiting · 1 issue assigned");
});
