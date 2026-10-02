#!/usr/bin/env node
// Logic tests for the Bluetooth tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/bluetooth/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Bt = require("./bluetooth.js");

const headphones = { address: "AA:BB:CC:DD:EE:01", name: "WH-1000XM5", icon: "audio-headset", connected: true, paired: true, batteryAvailable: true, battery: 0.85 };
const mouse = { address: "AA:BB:CC:DD:EE:02", deviceName: "MX Master 3S", name: "MX Master", icon: "input-mouse", connected: false, paired: true };
const stranger = { address: "AA:BB:CC:DD:EE:03", name: "[TV] Samsung", icon: "", connected: false, paired: false };
const nameless = { address: "AA:BB:CC:DD:EE:04", name: "AA-BB-CC-DD-EE-04", connected: true, paired: true };
const keyboard = { address: "AA:BB:CC:DD:EE:05", name: "Apple Keyboard", icon: "input-keyboard", connected: false, trusted: true };

test("rows keep known devices, connected first, then by name", () => {
  const rows = Bt.rows([mouse, stranger, keyboard, headphones, nameless], {}, 0);
  assert.deepEqual(rows.map((r) => r.name), ["WH-1000XM5", "Apple Keyboard", "MX Master 3S"]);
  assert.equal(rows[0].glyph, "󰋋");
  assert.equal(rows[0].battery, 85);
  assert.equal(rows[2].battery, null);
});

test("rows read a Quickshell-style list with a length", () => {
  const values = { length: 2, 0: headphones, 1: mouse };
  assert.equal(Bt.rows(values, {}, 0).length, 2);
  assert.deepEqual(Bt.rows(null, {}, 0), []);
});

test("a device listed twice shows once", () => {
  assert.equal(Bt.rows([headphones, headphones], {}, 0).length, 1);
});

test("a bad address never becomes a row", () => {
  assert.deepEqual(Bt.rows([{ ...mouse, address: "AA:BB:CC:DD:EE:0Z" }], {}, 0), []);
  assert.equal(Bt.isAddress("AA:BB:CC:DD:EE:FF"), true);
  assert.equal(Bt.isAddress("AA:BB:CC:DD:EE:FF; rm"), false);
  assert.equal(Bt.isAddress(""), false);
});

test("names that are only an address or a UUID are not human", () => {
  assert.equal(Bt.hasHumanName({ name: "04-E4-B6-D6-81-0D" }), false);
  assert.equal(Bt.hasHumanName({ name: "04:E4:B6:D6:81:0D" }), false);
  assert.equal(Bt.hasHumanName({ name: "0000110b-0000-1000-8000-00805f9b34fb" }), false);
  assert.equal(Bt.hasHumanName({ name: "  " }), false);
  assert.equal(Bt.hasHumanName({ name: "Pixel 9" }), true);
});

test("battery accepts 0..1 and percentages", () => {
  assert.equal(Bt.batteryPercent({ batteryAvailable: true, battery: 0.5 }), 50);
  assert.equal(Bt.batteryPercent({ batteryAvailable: true, battery: 73 }), 73);
  assert.equal(Bt.batteryPercent({ batteryAvailable: false, battery: 0.5 }), null);
  assert.equal(Bt.batteryPercent({ batteryAvailable: true, battery: NaN }), null);
});

test("pending clears when done or when it gets old", () => {
  const pending = Bt.withPending({}, mouse.address, "connect", 1000);
  assert.equal(Bt.pendingFor(pending, mouse.address, false, 2000), "connect");
  assert.equal(Bt.pendingFor(pending, mouse.address, true, 2000), "");
  assert.equal(Bt.pendingFor(pending, mouse.address, false, 1000 + Bt.PENDING_MS + 1), "");
  const off = Bt.withPending(pending, headphones.address, "disconnect", 1000);
  assert.equal(Bt.pendingFor(off, headphones.address, true, 2000), "disconnect");
  assert.equal(Bt.pendingFor(off, headphones.address, false, 2000), "");
  assert.equal(Object.keys(pending).length, 1, "withPending copies");
});

test("row notes", () => {
  assert.equal(Bt.rowNote({ connected: true, battery: 40, pending: "" }), "40%");
  assert.equal(Bt.rowNote({ connected: true, battery: null, pending: "" }), "connected");
  assert.equal(Bt.rowNote({ connected: false, battery: null, pending: "" }), "connect");
  assert.equal(Bt.rowNote({ connected: false, battery: null, pending: "connect" }), "connecting…");
  assert.equal(Bt.rowNote({ connected: true, battery: 9, pending: "disconnect" }), "disconnecting…");
});

test("status line", () => {
  assert.equal(Bt.status(null, []), "no adapter");
  assert.equal(Bt.status({ enabled: false }, []), "off");
  assert.equal(Bt.status({ enabled: true }, []), "on");
  assert.equal(Bt.status({ enabled: true }, [{ connected: true }, { connected: false }]), "1 connected");
});

test("glyphs by BlueZ icon", () => {
  assert.equal(Bt.glyphFor("audio-headphones"), "󰋋");
  assert.equal(Bt.glyphFor("audio-card"), "󰓃");
  assert.equal(Bt.glyphFor("input-gaming"), "󰊴");
  assert.equal(Bt.glyphFor("phone"), "󰏲");
  assert.equal(Bt.glyphFor(""), "󰂯");
});
