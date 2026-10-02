#!/usr/bin/env node
// Logic tests for the network tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/network/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Net = require("./network.js");

const wifi = { kind: "wifi", device: "wlan0", name: "Cafe", band: "5 GHz", signal: 72, at: 1000, rx: 1000, tx: 100, vpns: [] };

test("rate between two samples of the same interface", () => {
  const next = { ...wifi, at: 3000, rx: 5000, tx: 300 };
  assert.deepEqual(Net.rateBetween(wifi, next), { down: 2000, up: 100 });
});

test("no rate across interfaces, resets, or a stale gap", () => {
  assert.equal(Net.rateBetween(wifi, { ...wifi, device: "eth0", at: 3000 }), null);
  assert.equal(Net.rateBetween(wifi, { ...wifi, at: 3000, rx: 10 }), null);
  assert.equal(Net.rateBetween(wifi, { ...wifi, at: 1000 }), null);
  assert.equal(Net.rateBetween(wifi, { ...wifi, at: 1000 + 120000 }), null);
  assert.equal(Net.rateBetween(null, wifi), null);
});

test("falls back to the sampler's own first rate", () => {
  const first = { ...wifi, rate: { down: 42, up: 7 } };
  assert.deepEqual(Net.pickRate(null, first), { down: 42, up: 7 });
  assert.equal(Net.pickRate(null, wifi), null);
  const next = { ...wifi, at: 2000, rx: 2000, tx: 100, rate: { down: 1, up: 1 } };
  assert.deepEqual(Net.pickRate(wifi, next), { down: 1000, up: 0 });
});

test("history keeps the newest values", () => {
  let list = [];
  for (let i = 0; i < 50; i++) list = Net.pushHistory(list, i, 40);
  assert.equal(list.length, 40);
  assert.equal(list[0], 10);
  assert.equal(list[39], 49);
  assert.deepEqual(Net.pushHistory([1], -5, 40), [1, 0]);
});

test("formats rates and link speeds", () => {
  assert.equal(Net.fmtRate(0), "0 B/s");
  assert.equal(Net.fmtRate(999), "999 B/s");
  assert.equal(Net.fmtRate(1500), "1.5 KB/s");
  assert.equal(Net.fmtRate(23456), "23 KB/s");
  assert.equal(Net.fmtRate(123456), "123 KB/s");
  assert.equal(Net.fmtRate(1234567), "1.2 MB/s");
  assert.equal(Net.fmtRate(null), "—");
  assert.equal(Net.fmtLinkSpeed(2500), "2.5 Gb/s");
  assert.equal(Net.fmtLinkSpeed(1000), "1 Gb/s");
  assert.equal(Net.fmtLinkSpeed(100), "100 Mb/s");
  assert.equal(Net.fmtLinkSpeed(-1), "");
});

test("names and details per kind", () => {
  assert.equal(Net.title(wifi), "Cafe");
  assert.equal(Net.detail(wifi), "5 GHz · 72% · wlan0");
  const eth = { kind: "ethernet", device: "enp8s0", speed: 2500 };
  assert.equal(Net.title(eth), "Ethernet");
  assert.equal(Net.detail(eth), "2.5 Gb/s · enp8s0");
  const tun = { kind: "tunnel", device: "wg0", name: "WireGuard", via: "enp3s0" };
  assert.equal(Net.title(tun), "WireGuard");
  assert.equal(Net.detail(tun), "over enp3s0 · wg0");
  assert.equal(Net.title({ kind: "offline", device: "" }), "Offline");
  assert.equal(Net.detail({ kind: "offline", device: "" }), "No route to the internet");
  assert.equal(Net.title({ kind: "wifi", device: "wlan0", name: "" }), "Wi-Fi");
});

test("signal glyph steps", () => {
  assert.equal(Net.signalGlyph(95), "󰤨");
  assert.equal(Net.signalGlyph(65), "󰤥");
  assert.equal(Net.signalGlyph(45), "󰤢");
  assert.equal(Net.signalGlyph(25), "󰤟");
  assert.equal(Net.signalGlyph(5), "󰤯");
  assert.equal(Net.glyph({ kind: "ethernet" }), "󰈀");
  assert.equal(Net.glyph({ kind: "offline" }), "󰤮");
});

test("the VPN line leaves out the tunnel that is the title", () => {
  const vpns = [{ device: "wg0", name: "WireGuard" }, { device: "tailscale0", name: "Tailscale", detail: "exit via nas" }];
  assert.equal(Net.vpnLine({ ...wifi, vpns }), "WireGuard  Tailscale · exit via nas");
  assert.equal(Net.vpnLine({ kind: "tunnel", device: "wg0", vpns }), "Tailscale · exit via nas");
  assert.equal(Net.vpnLine(wifi), "");
});

test("latency", () => {
  assert.equal(Net.fmtLatency(4.26), "4.3 ms");
  assert.equal(Net.fmtLatency(12.7), "13 ms");
  assert.equal(Net.fmtLatency(null), "");
});

test("graph points share one scale and sit right-aligned", () => {
  const scale = Net.graphScale([0, 100000], [50000]);
  assert.ok(scale >= 100000);
  const pts = Net.graphPoints([0, scale], 100, 50, scale, 3);
  assert.deepEqual(pts, [{ x: 50, y: 50 }, { x: 100, y: 0 }]);
  assert.equal(Net.graphScale([], []), 16 * 1024);
});
