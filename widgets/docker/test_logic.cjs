#!/usr/bin/env node
// Logic tests for the docker widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/docker/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const { countsLine, statusLabel, statusHint } = require("./docker.js");

test("composes the counts line", () => {
  assert.equal(countsLine({ ok: true, running: 2, stopped: 3, unhealthy: 1 }),
               "1 unhealthy · 2 up · 3 down");
  assert.equal(countsLine({ ok: true, running: 2, stopped: 0 }), "2 up");
  assert.equal(countsLine({ ok: true, running: 0, stopped: 0 }), "0 up");
  assert.equal(countsLine({ ok: false, running: 9 }), "");
  assert.equal(countsLine(null), "");
});

test("labels the broken states", () => {
  assert.equal(statusLabel({ mode: "missing" }), "Docker not installed");
  assert.equal(statusLabel({ mode: "sudo" }), "Docker needs sudo");
  assert.equal(statusLabel({ mode: "error" }), "Docker unavailable");
  assert.equal(statusLabel({ mode: "rows", ok: true }), "");
  assert.equal(statusLabel(null), "Docker unavailable");
});

test("hints only for the sudo state", () => {
  assert.equal(statusHint({ mode: "sudo" }), "Enable sudoless Docker in Omarchy");
  assert.equal(statusHint({ mode: "missing" }), "");
  assert.equal(statusHint({ mode: "error" }), "");
  assert.equal(statusHint(null), "");
});
