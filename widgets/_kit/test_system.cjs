#!/usr/bin/env node
// Tests for system.js, the meters behind sysmon, sysdisk, and disks. Stdlib only.
//
// Run from the repo root:  node --test widgets/_kit/test_system.cjs

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

globalThis.Qt = { rgba: (r, g, b, a) => ({ r, g, b, a }) };
const Sys = require("./system.js");

const GiB = 1073741824;

describe("colors", () => {
  const text = { r: 1, g: 1, b: 1 };
  const urgent = { r: 1, g: 0, b: 0 };

  it("a comfortable meter is the text color, not the accent", () => {
    assert.deepEqual(Sys.fill(0.3, text, urgent), { r: 1, g: 1, b: 1, a: 1 });
    assert.deepEqual(Sys.fill(0.75, text, urgent), { r: 1, g: 1, b: 1, a: 1 });
  });

  it("blends into urgent between 75% and 90%", () => {
    const mid = Sys.fill(0.825, text, urgent);
    assert.ok(Math.abs(mid.g - 0.5) < 1e-9);
    assert.deepEqual(Sys.fill(0.95, text, urgent), { r: 1, g: 0, b: 0, a: 1 });
  });

  it("only a meter past 75% counts as hot", () => {
    assert.equal(Sys.isHot(0.74), false);
    assert.equal(Sys.isHot(0.75), true);
    assert.equal(Sys.heat(Number.NaN), 0);
  });
});

describe("cpu between samples", () => {
  const empty = { ticks: null, at: 0, cpu: null };

  it("needs two samples, then reads the busy share of the jiffies between them", () => {
    let state = Sys.cpuStep(empty, { cpuTicks: [1000, 800] }, 0);
    assert.equal(state.cpu, null);
    // 400 jiffies passed, 100 of them idle.
    state = Sys.cpuStep(state, { cpuTicks: [1400, 900] }, 1200);
    assert.equal(state.cpu, 75);
    assert.deepEqual(state.ticks, [1400, 900]);
  });

  it("takes a warm run's own reading and keeps its counters", () => {
    let state = Sys.cpuStep(empty, { cpuTicks: [1000, 800] }, 0);
    state = Sys.cpuStep(state, { cpu: 12.5, cpuTicks: [1040, 835] }, 150);
    assert.equal(state.cpu, 12.5);
    state = Sys.cpuStep(state, { cpuTicks: [1440, 1235] }, 1350);
    assert.equal(state.cpu, 0);
  });

  it("drops counters older than the ones it holds", () => {
    let state = Sys.cpuStep(empty, { cpuTicks: [2000, 1000] }, 0);
    state = Sys.cpuStep(state, { cpu: 30, cpuTicks: [1900, 950] }, 100);
    assert.equal(state.cpu, 30);
    assert.deepEqual(state.ticks, [2000, 1000]);
  });

  it("does not average over a closed tile", () => {
    let state = Sys.cpuStep(empty, { cpuTicks: [1000, 800] }, 0);
    state = Sys.cpuStep(state, { cpuTicks: [9000, 1000] }, Sys.CPU_GAP_MS + 1);
    assert.equal(state.cpu, null);
    assert.deepEqual(state.ticks, [9000, 1000]);
  });

  it("ignores missing or broken counters", () => {
    const state = Sys.cpuStep({ ticks: [10, 5], at: 0, cpu: 40 }, { cpuTicks: ["x", 1] }, 100);
    assert.equal(state.cpu, 40);
    assert.deepEqual(Sys.cpuStep(null, null, 0), { ticks: null, at: 0, cpu: null });
  });
});

describe("words", () => {
  it("names clocks in GHz and MHz", () => {
    assert.equal(Sys.clock(3940), "3.9 GHz");
    assert.equal(Sys.clock(885), "885 MHz");
    assert.equal(Sys.clock(0), "");
  });

  it("writes memory as used over total", () => {
    assert.equal(Sys.bytesPair(51.3 * GiB, 60.4 * GiB), "51.3 / 60.4 GiB");
    assert.equal(Sys.bytesPair(256 * 1048576, 512 * 1048576), "256 / 512 MiB");
    assert.equal(Sys.bytesPair(5, 0), "");
  });

  it("rounds temperatures and leaves out a missing one", () => {
    assert.equal(Sys.temp(60.2), "60°C");
    assert.equal(Sys.temp(null), "");
    assert.equal(Sys.temp(0), "");
  });
});

describe("meters", () => {
  const desktop = {
    cpuMHz: 3940, cpuTemp: 60.2, mem: 85.9, memUsed: 51.3 * GiB, memTotal: 60.4 * GiB,
    gpu: 4, gpuMHz: 540, gpuTemp: 51, gpuAsleep: false, vram: 29.4, vramUsed: 4.7 * GiB, vramTotal: 15.9 * GiB,
  };

  it("draws CPU, RAM, GPU, and VRAM with clocks and temperatures", () => {
    const rows = Sys.meters(desktop, 12.4);
    assert.deepEqual(rows.map((r) => r.key), ["cpu", "mem", "gpu", "vram"]);
    assert.deepEqual(rows[0], { key: "cpu", label: "CPU", value: 0.124, pct: "12%", sub: "3.9 GHz · 60°C" });
    assert.equal(rows[1].sub, "51.3 / 60.4 GiB");
    assert.equal(rows[2].sub, "540 MHz · 51°C");
    assert.equal(rows[3].pct, "29%");
  });

  it("shows no CPU figure before there is one", () => {
    const cpu = Sys.meters(desktop, null)[0];
    assert.equal(cpu.pct, "—");
    assert.equal(cpu.value, 0);
  });

  it("an Intel laptop has no VRAM row, and its GPU row shows the clock", () => {
    const rows = Sys.meters({ mem: 50, memUsed: 8 * GiB, memTotal: 16 * GiB, gpu: null, gpuMHz: 1300, vramTotal: 0 }, 5);
    assert.deepEqual(rows.map((r) => r.key), ["cpu", "mem", "gpu"]);
    assert.equal(rows[2].pct, "—");
    assert.equal(rows[2].sub, "1.3 GHz");
  });

  it("a machine with no GPU reading draws two rows", () => {
    const rows = Sys.meters({ mem: 50, memTotal: GiB, gpu: null, gpuMHz: 0 }, 5);
    assert.deepEqual(rows.map((r) => r.key), ["cpu", "mem"]);
  });

  it("a sleeping GPU says so instead of waking up to answer", () => {
    const rows = Sys.meters({ mem: 50, memTotal: GiB, gpu: null, gpuAsleep: true }, 5);
    assert.deepEqual(rows[2], { key: "gpu", label: "GPU", value: 0, pct: "0%", sub: "asleep" });
  });

  it("the hottest meter drives the header dot", () => {
    assert.ok(Math.abs(Sys.hottest(Sys.meters(desktop, 12.4)) - 0.859) < 1e-9);
    assert.equal(Sys.hottest([]), 0);
  });

  it("a peak holds, then falls back toward the bar", () => {
    let peaks = Sys.peaksStep({}, [{ key: "cpu", value: 0.9 }]);
    peaks = Sys.peaksStep(peaks, [{ key: "cpu", value: 0.2 }]);
    assert.ok(Math.abs(peaks.cpu - 0.88) < 1e-9);
  });
});

describe("spec lines", () => {
  it("lists only the specs it knows", () => {
    assert.deepEqual(Sys.specLines({ cpuModel: "AMD Ryzen 9 9950X", cpuCores: 16, cpuThreads: 32, gpuModel: "RTX" }),
      ["AMD Ryzen 9 9950X · 16C/32T", "RTX"]);
    assert.deepEqual(Sys.specLines({}), []);
  });
});
