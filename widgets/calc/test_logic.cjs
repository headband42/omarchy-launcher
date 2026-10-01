#!/usr/bin/env node
// Logic tests for the calculator widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/calc/test_logic.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

// Stable Qt values (unchanged across Qt 5/6). calc.js reads the global Qt
// the way it does inside QML.
const Qt = {
  Key_0: 0x30, Key_5: 0x35, Key_9: 0x39, Key_Slash: 0x2f,
  Key_Asterisk: 0x2a, Key_Minus: 0x2d, Key_Plus: 0x2b,
  Key_Period: 0x2e, Key_A: 0x41,
  NoModifier: 0x00, KeypadModifier: 0x20000000,
};
globalThis.Qt = Qt;

const Calc = require("./calc.js");

const evalExpr = (expr) => Calc.parseExpr(Calc.tokenize(expr));

const pressKeys = (keys) => {
  let state = { expr: "", display: "0", preview: "" };
  for (const key of keys) state = Calc.press(state, key);
  return state;
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

describe("key text derivation", () => {
  const cases = [
    ["event text wins", "Key_5", "NoModifier", "5", "5"],
    ["comma means dot", "Key_5", "NoModifier", ",", "."],
    ["digit from key code without text", "Key_5", "NoModifier", "", "5"],
    ["pad slash without text", "Key_Slash", "KeypadModifier", "", "/"],
    ["pad period without text", "Key_Period", "KeypadModifier", "", "."],
    ["letters are not keys", "Key_A", "KeypadModifier", "", ""],
    ["slash without pad modifier is ignored", "Key_Slash", "NoModifier", "", ""],
  ];
  for (const [name, key, mods, text, want] of cases) {
    it(name, () => assert.equal(
      Calc.keyText(Qt[key], Qt[mods], text), want));
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
