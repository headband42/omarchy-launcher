#!/usr/bin/env node
// Logic tests for the repo widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/repo/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Repo = require("./repo.js");

test("names the branch", () => {
  assert.equal(Repo.branchLine({ ok: true, branch: "main" }), "main");
  assert.equal(Repo.branchLine({ ok: true, detached: true }), "detached HEAD");
  assert.equal(Repo.branchLine({ ok: true, branch: "" }), "");
  assert.equal(Repo.branchLine({ ok: false, branch: "main" }), "");
  assert.equal(Repo.branchLine(null), "");
});

test("says what the branch tracks", () => {
  assert.equal(Repo.upstreamLine({ ok: true, branch: "main", hash: "abc", upstream: "origin/main" }), "origin/main");
  assert.equal(Repo.upstreamLine({ ok: true, branch: "main", hash: "abc", upstream: "" }), "no upstream");
  assert.equal(Repo.upstreamLine({ ok: true, branch: "main", hash: "" }), "no commits yet");
  assert.equal(Repo.upstreamLine({ ok: true, detached: true, hash: "abc1234" }), "at abc1234");
  assert.equal(Repo.upstreamLine({ ok: false }), "");
});

test("builds the file-state chips", () => {
  const sample = { ok: true, conflicted: 1, staged: 2, modified: 3, untracked: 4, stash: 2 };
  assert.deepEqual(Repo.chips(sample).map((c) => c.label),
                   ["1 conflict", "2 staged", "3 modified", "4 new", "2 stashed"]);
  assert.equal(Repo.chips({ ok: true, conflicted: 2 })[0].label, "2 conflicts");
  assert.equal(Repo.chips({ ok: true, conflicted: 2 })[0].tone, "urgent");
  assert.deepEqual(Repo.chips({ ok: true }).map((c) => c.key), ["clean"]);
  assert.deepEqual(Repo.chips({ ok: true, stash: 1 }).map((c) => c.key), ["clean", "stash"]);
  assert.deepEqual(Repo.chips({ ok: false, staged: 3 }), []);
  assert.deepEqual(Repo.chips(null), []);
});

test("reads the tree state for the header dot", () => {
  assert.equal(Repo.state({ ok: true, conflicted: 1, modified: 2 }), "conflict");
  assert.equal(Repo.state({ ok: true, untracked: 1 }), "dirty");
  assert.equal(Repo.state({ ok: true, staged: 1 }), "dirty");
  assert.equal(Repo.state({ ok: true, stash: 3 }), "clean");
  assert.equal(Repo.state({ ok: false }), "");
});

test("pads and trims the activity strip to two weeks", () => {
  assert.equal(Repo.activity({}).length, 14);
  assert.deepEqual(Repo.activity({ activity: [1, 2, 3] }).slice(-3), [1, 2, 3]);
  assert.deepEqual(Repo.activity({ activity: [1, 2, 3] }).slice(0, 11), new Array(11).fill(0));
  const long = Array.from({ length: 20 }, (_, i) => i);
  assert.deepEqual(Repo.activity({ activity: long }), long.slice(6));
  assert.deepEqual(Repo.activity({ activity: [-2, "x", 2.7] }).slice(-3), [0, 0, 2]);
  assert.equal(Repo.total([1, 2, 3]), 6);
  assert.equal(Repo.peak([1, 5, 3]), 5);
  assert.equal(Repo.peak([]), 0);
});

test("scales a day's bar with a floor for quiet days", () => {
  assert.equal(Repo.barLevel(0, 10), 0);
  assert.equal(Repo.barLevel(10, 10), 1);
  assert.equal(Repo.barLevel(5, 10), 0.5);
  assert.equal(Repo.barLevel(1, 50), 0.18);
  assert.equal(Repo.barLevel(3, 0), 0);
});

test("labels ages", () => {
  const now = 1_800_000_000;
  assert.equal(Repo.ageLabel(now - 30, now), "now");
  assert.equal(Repo.ageLabel(now - 5 * 60, now), "5m");
  assert.equal(Repo.ageLabel(now - 3 * 3600, now), "3h");
  assert.equal(Repo.ageLabel(now - 2 * 86400, now), "2d");
  assert.equal(Repo.ageLabel(now - 21 * 86400, now), "3w");
  assert.equal(Repo.ageLabel(now - 120 * 86400, now), "4mo");
  assert.equal(Repo.ageLabel(now - 800 * 86400, now), "2y");
  assert.equal(Repo.ageLabel(now + 500, now), "now");
  assert.equal(Repo.ageLabel(0, now), "");
  assert.equal(Repo.ageLabel(now, 0), "");
});

test("says when the upstream was last fetched", () => {
  const now = 1_800_000_000;
  assert.equal(Repo.fetchedLine({ ok: true, upstream: "origin/main", fetchedAt: now - 7200 }, now), "fetched 2h ago");
  assert.equal(Repo.fetchedLine({ ok: true, upstream: "origin/main", fetchedAt: now - 5 }, now), "fetched just now");
  assert.equal(Repo.fetchedLine({ ok: true, upstream: "origin/main", fetchedAt: 0 }, now), "never fetched");
  assert.equal(Repo.fetchedLine({ ok: true, upstream: "", fetchedAt: now }, now), "");
  assert.equal(Repo.fetchedLine(null, now), "");
});

test("marks the commits the upstream does not have", () => {
  const sample = { upstream: "origin/main", ahead: 2 };
  assert.equal(Repo.unpushed(sample, 0), true);
  assert.equal(Repo.unpushed(sample, 1), true);
  assert.equal(Repo.unpushed(sample, 2), false);
  assert.equal(Repo.unpushed({ upstream: "", ahead: 5 }, 0), false);
  assert.equal(Repo.unpushed(sample, -1), false);
});

test("shortens paths under home", () => {
  assert.equal(Repo.displayPath("/home/u/src/app", "/home/u"), "~/src/app");
  assert.equal(Repo.displayPath("/home/u", "/home/u/"), "~");
  assert.equal(Repo.displayPath("/home/user2/app", "/home/u"), "/home/user2/app");
  assert.equal(Repo.displayPath("~/src", "/home/u"), "~/src");
  assert.equal(Repo.displayPath("/srv/app", ""), "/srv/app");
});

test("stores a typed path, or forgets it", () => {
  assert.deepEqual(Repo.settingsFromPath("  ~/src/app "), { path: "~/src/app" });
  assert.deepEqual(Repo.settingsFromPath("   "), {});
  assert.deepEqual(Repo.settingsFromPath(null), {});
});

test("copies array-likes from QML", () => {
  assert.deepEqual(Repo.toList({ length: 2, 0: "a", 1: "b" }), ["a", "b"]);
  assert.deepEqual(Repo.toList(null), []);
});
