#!/usr/bin/env node
// Logic tests for the repo widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/repo/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const { countsLine, branchLine } = require("./repo.js");

test("composes the counts line", () => {
  assert.equal(countsLine({ ok: true, ahead: 2, behind: 1, dirty: 3, untracked: 2, conflicted: 1 }),
               "+2 -1 · 3 changed · 2 new · 1 conflicted");
  assert.equal(countsLine({ ok: true, ahead: 0, behind: 3, dirty: 1 }), "-3 · 1 changed");
  assert.equal(countsLine({ ok: true, ahead: 1 }), "+1");
  assert.equal(countsLine({ ok: true }), "");
  assert.equal(countsLine({ ok: false, dirty: 9 }), "");
  assert.equal(countsLine(null), "");
});

test("names the branch", () => {
  assert.equal(branchLine({ ok: true, branch: "main" }), "main");
  assert.equal(branchLine({ ok: true, detached: true }), "detached HEAD");
  assert.equal(branchLine({ ok: true, branch: "" }), "");
  assert.equal(branchLine(null), "");
});
