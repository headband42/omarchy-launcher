#!/usr/bin/env node
// Tests for the shared widget helpers. Stdlib only.
//
// Run from the repo root:  node --test widgets/_kit/test_kit.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const { localPath } = require("./kit.js");

describe("localPath", () => {
  it("turns a file URL into a path", () => {
    assert.equal(localPath("file:///opt/widgets/battery/battery.py"), "/opt/widgets/battery/battery.py");
  });

  it("decodes escaped characters", () => {
    assert.equal(localPath("file:///home/a%20b/w%C3%A9ather.py"), "/home/a b/wéather.py");
  });

  it("takes a URL object like Qt.resolvedUrl returns", () => {
    assert.equal(localPath(new URL("file:///tmp/x.py")), "/tmp/x.py");
  });

  it("leaves a plain path and an empty value alone", () => {
    assert.equal(localPath("/tmp/x.py"), "/tmp/x.py");
    assert.equal(localPath(""), "");
    assert.equal(localPath(undefined), "");
  });
});
