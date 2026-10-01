#!/usr/bin/env node
// Logic tests for the docker widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/docker/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Docker = require("./docker.js");

test("labels the states with no rows", () => {
  assert.equal(Docker.statusLabel({ mode: "missing" }), "Docker isn’t installed");
  assert.equal(Docker.statusLabel({ mode: "sudo" }), "Docker needs your password");
  assert.equal(Docker.statusLabel({ mode: "idle" }), "Docker is idle");
  assert.equal(Docker.statusLabel({ mode: "stopped" }), "Docker is stopped");
  assert.equal(Docker.statusLabel({ mode: "error" }), "Docker unavailable");
  assert.equal(Docker.statusLabel({ mode: "rows", ok: true, rows: [] }), "No containers");
  assert.equal(Docker.statusLabel({ mode: "rows", ok: true, rows: [{}] }), "");
  assert.equal(Docker.statusLabel(null), "Docker unavailable");
});

test("says what the daemon is doing without the socket", () => {
  assert.equal(Docker.statusDetail({ mode: "sudo", daemon: "running", scoped: 3 }), "Daemon running · 3 containers");
  assert.equal(Docker.statusDetail({ mode: "sudo", daemon: "running", scoped: 1 }), "Daemon running · 1 container");
  assert.equal(Docker.statusDetail({ mode: "sudo", daemon: "running", scoped: 0 }), "Daemon running");
  assert.equal(Docker.statusDetail({ mode: "sudo", daemon: "idle" }), "Daemon idle · starts on first use");
  assert.equal(Docker.statusDetail({ mode: "sudo", daemon: "" }), "");
  assert.equal(Docker.statusDetail({ mode: "idle" }), "The socket starts it on first use");
  assert.equal(Docker.statusDetail({ mode: "missing" }), "");
});

test("hints at the way out", () => {
  assert.equal(Docker.statusHint({ mode: "sudo" }), "Setup › Security › Sudoless Docker skips the prompt");
  assert.equal(Docker.statusHint({ mode: "sudo", pendingLogin: true }),
               "Sudoless Docker is set up. Log out and back in to use it.");
  assert.equal(Docker.statusHint({ mode: "stopped" }), "systemctl enable --now docker.socket");
  assert.equal(Docker.statusHint({ mode: "missing" }), "");
  assert.equal(Docker.statusHint(null), "");
});

test("offers lazydocker only when it could connect", () => {
  assert.equal(Docker.canOpen({ mode: "sudo" }), true);
  assert.equal(Docker.canOpen({ mode: "idle" }), true);
  assert.equal(Docker.canOpen({ mode: "error" }), true);
  assert.equal(Docker.canOpen({ mode: "missing" }), false);
  assert.equal(Docker.canOpen({ mode: "stopped" }), false);
});

test("builds the stat blocks", () => {
  assert.deepEqual(Docker.stats({ ok: true, running: 2, stopped: 1 }).map((s) => s.key), ["running", "stopped"]);
  assert.deepEqual(Docker.stats({ ok: true, running: 2, unhealthy: 1, paused: 1, stopped: 0 }).map((s) => [s.key, s.count]),
                   [["running", 2], ["unhealthy", 1], ["paused", 1], ["stopped", 0]]);
  assert.deepEqual(Docker.stats({ ok: false, running: 3 }), []);
});

test("formats bytes and CPU compactly", () => {
  assert.equal(Docker.formatBytes(0), "0B");
  assert.equal(Docker.formatBytes(512), "512B");
  assert.equal(Docker.formatBytes(84.2 * 1024 * 1024), "84M");
  assert.equal(Docker.formatBytes(1.6 * 1024 ** 3), "1.6G");
  assert.equal(Docker.formatBytes(2 * 1024 ** 3), "2G");
  assert.equal(Docker.formatBytes(null), "0B");
  assert.equal(Docker.formatCpu(0), "0%");
  assert.equal(Docker.formatCpu(0.05), "0.1%");
  assert.equal(Docker.formatCpu(2.0), "2%");
  assert.equal(Docker.formatCpu(12.4), "12%");
  assert.equal(Docker.formatCpu(205.6), "206%");
});

test("composes the header usage once anything runs", () => {
  assert.equal(Docker.usageLine({ ok: true, running: 2, cpu: 14.9, mem: 1.6 * 1024 ** 3 }), "15% · 1.6G");
  assert.equal(Docker.usageLine({ ok: true, running: 0, cpu: 0, mem: 0 }), "");
  assert.equal(Docker.usageLine({ ok: false, running: 2 }), "");
});

test("describes a row", () => {
  assert.equal(Docker.rowDetail({ name: "immich_server", project: "immich", image: "immich-server:release", ports: ["2283"] }),
               "immich · immich-server:release · :2283");
  assert.equal(Docker.rowDetail({ name: "web", project: "web", image: "nginx" }), "nginx");
  assert.equal(Docker.rowDetail({ name: "x", image: "", ports: ["80", "443"] }), ":80 :443");
  assert.equal(Docker.rowDetail(null), "");
  assert.equal(Docker.rowUsage({ running: true, cpu: 2.15, mem: 84 * 1024 * 1024 }), "2.1% · 84M");
  assert.equal(Docker.rowUsage({ running: true, cpu: null }), "");
  assert.equal(Docker.rowUsage({ running: false, cpu: 1, mem: 1 }), "");
});

test("offers the actions that fit the state", () => {
  assert.deepEqual(Docker.actionsFor({ id: "a", state: "running" }), ["restart", "stop"]);
  assert.deepEqual(Docker.actionsFor({ id: "a", state: "restarting" }), ["stop"]);
  assert.deepEqual(Docker.actionsFor({ id: "a", state: "exited" }), ["start"]);
  assert.deepEqual(Docker.actionsFor({ id: "a", state: "created" }), ["start"]);
  assert.deepEqual(Docker.actionsFor({ id: "a", state: "paused" }), []);
  assert.deepEqual(Docker.actionsFor({ state: "running" }), []);
});

test("plans rows with room for the overflow line", () => {
  assert.deepEqual(Docker.rowPlan(3, 200, 30, 16), { rows: 3, more: 0 });
  assert.deepEqual(Docker.rowPlan(8, 200, 30, 16), { rows: 6, more: 2 });
  assert.deepEqual(Docker.rowPlan(7, 180, 30, 16), { rows: 5, more: 2 });
  assert.deepEqual(Docker.rowPlan(0, 200, 30, 16), { rows: 0, more: 0 });
  assert.deepEqual(Docker.rowPlan(4, 10, 30, 16), { rows: 0, more: 4 });
});
