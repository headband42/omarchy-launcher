#!/usr/bin/env node
// Logic tests for the calculator widget. Stdlib only.
//
// The expression core and key handling are plain JS shipped inside
// Widget.qml, so this file executes that exact code against a fake
// root object instead of a copy.
//
// Run from the repo root:  node --test widgets/calc/test_logic.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const SRC = fs.readFileSync(path.join(__dirname, "Widget.qml"), "utf8");
const CODE = SRC.slice(SRC.indexOf("  function tokenize(input)"),
                       SRC.indexOf("  function keyFill"));

const load = (root, Qt) => new Function(
  "root", "Qt", `${CODE}; return {tokenize, parseExpr, press, padDigit};`)(root, Qt);

// Stable Qt::Key values (unchanged across Qt 5/6).
const Qt = {
  Key_Insert: 0x01000006, Key_End: 0x01000003, Key_Down: 0x01000015,
  Key_PageDown: 0x01000016, Key_Left: 0x01000012, Key_Clear: 0x0100000B,
  Key_Right: 0x01000014, Key_Home: 0x01000010, Key_Up: 0x01000013,
  Key_PageUp: 0x01000011, Key_A: 0x41,
};

const evalExpr = (expr) => {
  const fns = load({});
  return fns.parseExpr(fns.tokenize(expr));
};

const pressKeys = (keys) => {
  const root = { expr: "", display: "0", preview: "" };
  const fns = load(root);
  for (const key of keys) fns.press(key);
  return root;
};

describe("expression core", () => {
  const cases = [
    ["2+3*4", 14],
    ["(2+3)*4", 20],
    ["-5+2", -3],
    ["3.5*2", 7],
    [".5+.5", 1],
    ["2*(3+4)/2", 7],
    ["1/0", null],
    ["5+", null],
    ["", null],
    ["2&3", null],
  ];
  for (const [expr, want] of cases) {
    it(JSON.stringify(expr), () => assert.equal(evalExpr(expr), want));
  }
});

describe("numpad with NumLock off", () => {
  const cases = [
    ["Insert", "Key_Insert", "0"],
    ["End", "Key_End", "1"],
    ["Down", "Key_Down", "2"],
    ["PageDown", "Key_PageDown", "3"],
    ["Left", "Key_Left", "4"],
    ["Clear", "Key_Clear", "5"],
    ["Right", "Key_Right", "6"],
    ["Home", "Key_Home", "7"],
    ["Up", "Key_Up", "8"],
    ["PageUp", "Key_PageUp", "9"],
    ["other keys pass through", "Key_A", ""],
  ];
  for (const [name, key, want] of cases) {
    it(name, () => assert.equal(load({}, Qt).padDigit(Qt[key]), want));
  }
});

describe("key sequences", () => {
  const cases = [
    ["decimal entry",
     ["2", ".", "5", "+", "1"],
     { expr: "2.5+1", display: "2.5+1", preview: "= 3.5" }],
    ["equals commits and clears preview",
     ["2", "+", "2", "="],
     { expr: "4", display: "4", preview: "" }],
    ["backspace trims and re-previews",
     ["3", ".", "5", "←"],
     { expr: "3.", display: "3.", preview: "= 3" }],
    ["backspace to empty resets",
     ["5", "←", "←"],
     { expr: "", display: "0", preview: "" }],
    ["second dot in a segment is ignored",
     ["3", ".", "1", ".", "4"],
     { expr: "3.14", display: "3.14", preview: "= 3.14" }],
    ["divide by zero errors",
     ["1", "/", "0", "="],
     { expr: "1/0", display: "Err", preview: "" }],
    ["typing after error resets",
     ["1", "/", "0", "=", "5"],
     { expr: "5", display: "5", preview: "= 5" }],
    ["parenthesised expression",
     ["(", "2", "+", "3", ")", "*", "4", "="],
     { expr: "20", display: "20", preview: "" }],
    ["incomplete expression shows no preview",
     ["2", "+"],
     { expr: "2+", display: "2+", preview: "" }],
    ["clear resets everything",
     ["2", "+", "C"],
     { expr: "", display: "0", preview: "" }],
  ];
  for (const [name, keys, want] of cases) {
    it(name, () => assert.deepEqual(pressKeys(keys), want));
  }
});
