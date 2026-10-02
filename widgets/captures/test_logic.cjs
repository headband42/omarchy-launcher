#!/usr/bin/env node
// Logic tests for the captures tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/captures/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const C = require("./captures.js");

test("every action is one of Omarchy's capture commands", () => {
  for (const action of C.ACTIONS) {
    assert.match(action.argv[0], /^omarchy-capture-(screenshot|screenrecording)$/);
  }
  assert.deepEqual(C.ACTIONS.map((a) => a.id), ["smart", "windows", "fullscreen", "record"]);
});

test("a delayed capture keeps its argv out of the shell text", () => {
  const argv = C.delayed(["omarchy-capture-screenshot", "smart"], 0.45);
  assert.deepEqual(argv, ["bash", "-c", 'sleep "$1"; shift; exec "$@"', "bash", "0.45", "omarchy-capture-screenshot", "smart"]);
});

test("copy passes the path and type as arguments", () => {
  const argv = C.copyArgv("/home/u/Pictures/a b$(id).png");
  assert.equal(argv[2], 'wl-copy --type "$2" < "$1"');
  assert.equal(argv[4], "/home/u/Pictures/a b$(id).png");
  assert.equal(argv[5], "image/png");
  assert.equal(C.mimeFor("x.JPG"), "image/jpeg");
  assert.equal(C.mimeFor("x.webp"), "image/webp");
});

test("times and sizes", () => {
  assert.equal(C.fmtAgo(1000, 0), "");
  assert.equal(C.fmtAgo(1000, 990), "just now");
  assert.equal(C.fmtAgo(10000, 10000 - 7200), "2h ago");
  assert.equal(C.fmtAgo(10000000, 10000000 - 3 * 86400), "3d ago");
  assert.equal(C.fmtElapsed(42), "0:42");
  assert.equal(C.fmtElapsed(3725), "1:02:05");
  assert.equal(C.fmtSize(1500), "2 KB");
  assert.equal(C.fmtSize(2500000), "2.5 MB");
});

test("captions", () => {
  assert.equal(C.shotCaption({ mtime: 100, width: 3440, height: 1440 }, 100 + 7200), "2h ago · 3440×1440");
  assert.equal(C.shotCaption({ mtime: 100 }, 130), "just now");
  assert.equal(C.shotCaption(null, 0), "");
  assert.equal(C.headerNote({ recordingActive: true, recordingSince: 100 }, 142), "REC 0:42");
  assert.equal(C.headerNote({ recordingActive: true }, 142), "REC");
  assert.equal(C.headerNote({ today: 3 }, 0), "3 today");
  assert.equal(C.headerNote({ today: 0 }, 0), "");
});
