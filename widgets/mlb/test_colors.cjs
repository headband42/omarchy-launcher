#!/usr/bin/env node
// Club color map for the MLB tile. Stdlib only.
// Run from the repo root:  node --test widgets/mlb/test_colors.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { palette, COLORS } = require("./colors.js");

const LOGO_DIR = path.join(__dirname, "logos");

describe("team colors", () => {
  it("covers every bundled logo", () => {
    const logos = fs.readdirSync(LOGO_DIR).filter((name) => name.endsWith(".png"));
    assert.ok(logos.length >= 30);
    for (const name of logos) {
      const id = name.slice(0, -4);
      const colors = palette(id);
      assert.ok(colors, id);
      assert.match(colors.background, /^#[0-9A-Fa-f]{6}$/);
      assert.match(colors.text, /^#[0-9A-Fa-f]{6}$/);
      assert.match(colors.accent, /^#[0-9A-Fa-f]{6}$/);
    }
  });

  it("returns the Mariners navy and nothing for an unknown club", () => {
    assert.equal(palette(136).background, "#0C2C56");
    assert.equal(palette("147").text, "#FFFFFF");
    assert.equal(palette(0), null);
    assert.equal(palette(999999), null);
    assert.equal(Object.keys(COLORS).length, 30);
  });
});
