#!/usr/bin/env node
// Logic tests for the status tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/status/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("./status.js");

const catalog = [
  { id: "github", name: "GitHub", host: "www.githubstatus.com" },
  { id: "cloudflare", name: "Cloudflare", host: "www.cloudflarestatus.com" },
  { id: "gcp", name: "Google Cloud", host: "status.cloud.google.com" },
];

test("problems float up, worst first, others keep their order", () => {
  const rows = [
    { key: "a", state: "none" }, { key: "b", state: "minor" }, { key: "c", state: "unknown" },
    { key: "d", state: "critical" }, { key: "e", state: "maintenance" }, { key: "f", state: "none" },
  ];
  assert.deepEqual(S.sortRows(rows).map((r) => r.key), ["d", "b", "a", "c", "e", "f"]);
  assert.deepEqual(S.sortRows(null), []);
});

test("header note", () => {
  assert.equal(S.headerNote([]), "");
  assert.equal(S.headerNote([{ state: "none" }, { state: "none" }]), "all good");
  assert.equal(S.headerNote([{ state: "none" }, { state: "major" }]), "1 issue");
  assert.equal(S.headerNote([{ state: "down" }, { state: "minor" }]), "2 issues");
  assert.equal(S.headerNote([{ state: "none" }, { state: "maintenance" }]), "maintenance");
  assert.equal(S.headerNote([{ state: "unknown" }]), "no answer");
});

test("state labels", () => {
  assert.equal(S.stateLabel("none"), "ok");
  assert.equal(S.stateLabel("minor"), "degraded");
  assert.equal(S.stateLabel("critical"), "major outage");
  assert.equal(S.stateLabel("bogus"), "unknown");
  assert.equal(S.isProblem("minor"), true);
  assert.equal(S.isProblem("maintenance"), false);
});

test("settings round trip", () => {
  assert.equal(S.services({}), null);
  assert.equal(S.services(null), null);
  const custom = { url: "https://nas.local", kind: "http", name: "NAS" };
  const list = S.services({ services: ["github", "github", custom, { url: "https://nas.local", kind: "http" }, 5] });
  assert.deepEqual(list, ["github", custom]);
  assert.deepEqual(S.settingsFrom(list), { services: ["github", custom] });
});

test("add, remove, move", () => {
  let list = ["github"];
  list = S.withAdded(list, "cloudflare");
  list = S.withAdded(list, "cloudflare");
  assert.deepEqual(list, ["github", "cloudflare"]);
  assert.deepEqual(S.withMoved(list, 1, -1), ["cloudflare", "github"]);
  assert.deepEqual(S.withMoved(list, 0, -1), list);
  assert.deepEqual(S.withRemoved(list, 0), ["cloudflare"]);
  assert.deepEqual(S.withRemoved(list, 9), list);
  const full = Array.from({ length: S.MAX_SERVICES }, (_, i) => "s" + i);
  assert.equal(S.withAdded(full, "more").length, S.MAX_SERVICES);
});

test("catalog search by name, host, and id; marks what is added", () => {
  const hits = S.filterCatalog(catalog, "clo", ["cloudflare"]);
  assert.deepEqual(hits.map((h) => [h.id, h.added]), [["cloudflare", true], ["gcp", false]]);
  assert.equal(S.filterCatalog(catalog, "githubstatus", []).length, 1);
  assert.equal(S.filterCatalog(catalog, "", []).length, 3);
});

test("what looks like a web address", () => {
  for (const ok of ["nas.local", "nas.local:8080", "https://example.com/health", "status.example.com", "homeassistant:8123"])
    assert.equal(S.looksLikeUrl(ok), true, ok);
  for (const bad of ["github", "clo", "", "https://", "two words.com"])
    assert.equal(S.looksLikeUrl(bad), false, bad);
});

test("names", () => {
  assert.equal(S.nameFor("github", catalog), "GitHub");
  assert.equal(S.nameFor({ url: "https://nas.local", name: "NAS" }, catalog), "NAS");
  assert.equal(S.nameFor("unknown", catalog), "unknown");
});
