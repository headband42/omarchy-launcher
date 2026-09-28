// Logic tests for the Herdr tile's formatters. Stdlib only.
//
// herdr.js is the shipped file that Widget.qml and Settings.qml import, so
// this exercises that exact code rather than a copy of it.
//
// Run from the repo root:  node --test widgets/herdr/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Herdr = require("./herdr.js");

const working = {
  paneId: "w1:p2",
  tabId: "w1:t1",
  workspaceId: "w1",
  name: "muse",
  title: "Push repo to GitHub",
  status: "working",
  focused: false,
  cwd: "Projects/omarchy-launcher"
};

const blocked = {
  paneId: "w1:p3",
  name: "grok",
  title: "Which model?",
  status: "blocked",
  focused: false
};

const idle = {
  paneId: "w1:p4",
  name: "opencode",
  title: "OC | Pushing current branch",
  status: "idle",
  focused: true,
  cwd: "Projects/omarchy-launcher-weather"
};

const counts = { blocked: 1, working: 2, idle: 3, done: 0, unknown: 0 };

test("the status enum is passed through, and anything else is unknown", () => {
  for (const status of ["idle", "working", "blocked", "done", "unknown"]) {
    assert.equal(Herdr.statusOf({ status }), status);
  }
  assert.equal(Herdr.statusOf({ status: "thinking" }), "unknown");
  assert.equal(Herdr.statusOf({}), "unknown");
  assert.equal(Herdr.statusOf(null), "unknown");
  assert.deepEqual(Herdr.STATUSES, ["blocked", "working", "idle", "done", "unknown"]);
});

test("a status maps to a palette token, not a color", () => {
  // blocked borrows the urgent color: it is the one that needs a person.
  assert.equal(Herdr.statusTone("blocked"), "urgent");
  assert.equal(Herdr.statusTone("working"), "accent");
  assert.equal(Herdr.statusTone("done"), "quiet");
  assert.equal(Herdr.statusTone("idle"), "muted");
  assert.equal(Herdr.statusTone("unknown"), "muted");
  assert.equal(Herdr.statusTone("nonsense"), "muted");
  assert.equal(Herdr.statusLabel("working"), "WORKING");
  assert.equal(Herdr.statusLabel("nonsense"), "UNKNOWN");
});

test("blocked and working are the statuses that move", () => {
  assert.equal(Herdr.isBusy("blocked"), true);
  assert.equal(Herdr.isBusy("working"), true);
  assert.equal(Herdr.isBusy("idle"), false);
  assert.equal(Herdr.isBusy("done"), false);
  assert.equal(Herdr.isBusy(undefined), false);
  assert.equal(Herdr.needsAttention(counts), 3);
  assert.equal(Herdr.needsAttention(null), 0);
});

test("the header names the one status worth glancing at", () => {
  assert.equal(Herdr.headline(counts), "1 BLOCKED");
  assert.equal(Herdr.headline({ blocked: 0, working: 2, idle: 1 }), "2 WORKING");
  assert.equal(Herdr.headline({ blocked: 0, working: 0, idle: 4 }), "4 IDLE");
  assert.equal(Herdr.headline({ blocked: 0, working: 0, idle: 2, done: 1 }), "ALL QUIET");
  assert.equal(Herdr.headline({ blocked: 0, working: 0, idle: 0, done: 0 }), "NO AGENTS");
  assert.equal(Herdr.headline(null), "NO AGENTS");
  // Three blocked is still one number and one word.
  assert.equal(Herdr.headline({ blocked: 3 }), "3 BLOCKED");
  assert.equal(Herdr.headlineTone(counts), "urgent");
  assert.equal(Herdr.headlineTone({ working: 1 }), "accent");
  assert.equal(Herdr.headlineTone({ idle: 1 }), "muted");
});

test("the summary lists what is there and drops the rest", () => {
  assert.equal(Herdr.summary(counts), "1 blocked · 2 working · 3 idle");
  assert.equal(Herdr.summary({ blocked: 0, working: 0, idle: 0, done: 0, unknown: 0 }), "no agents");
  assert.equal(Herdr.summary({ working: 1 }), "1 working");
  assert.equal(Herdr.summary(null), "no agents");
  assert.equal(Herdr.countFor(counts, "idle"), 3);
  assert.equal(Herdr.countFor(counts, "done"), 0);
  assert.equal(Herdr.countFor(null, "idle"), 0);
  assert.equal(Herdr.countFor({}, "idle"), 0);
});

test("a row falls back through name, title, then directory", () => {
  assert.equal(Herdr.agentName(working), "muse");
  assert.equal(Herdr.agentName({}), "pane");
  assert.equal(Herdr.agentName(null), "pane");
  assert.equal(Herdr.agentTitle(working), "Push repo to GitHub");
  assert.equal(Herdr.agentTitle({}), "");
  assert.equal(Herdr.agentTitle({ cwd: "Projects/thing" }), "Projects/thing");
  // One letter is enough to tell two agents apart at tile size.
  assert.equal(Herdr.initial(working), "M");
  assert.equal(Herdr.initial({ name: "opencode" }), "O");
  assert.equal(Herdr.initial({}), "?");
  assert.equal(Herdr.isFocused(idle), true);
  assert.equal(Herdr.isFocused(working), false);
  assert.equal(Herdr.isFocused(null), false);
});

test("the agent list is a list, or empty", () => {
  assert.equal(Herdr.agentsOf({ agents: [working, idle] }).length, 2);
  assert.equal(Herdr.agentsOf({ agents: [] }).length, 0);
  assert.equal(Herdr.agentsOf({}).length, 0);
  assert.equal(Herdr.agentsOf(null).length, 0);
});

test("a scrolled window reports what is off screen", () => {
  // Seven rows, three visible, scrolled to the second.
  const win = Herdr.visibleWindow(40, 20, 7, 3);
  assert.equal(win.index, 3);
  assert.equal(win.total, 7);
  assert.equal(win.above, 2);
  assert.equal(win.below, 2);
  assert.equal(win.text, "3/7");
  // At the top, everything is below.
  const top = Herdr.visibleWindow(0, 20, 7, 3);
  assert.equal(top.above, 0);
  assert.equal(top.below, 4);
  // At the bottom, everything is above.
  const bottom = Herdr.visibleWindow(999, 20, 7, 3);
  assert.equal(bottom.below, 0);
  assert.equal(bottom.above, 4);
  // It never scrolls past the end, however far it is dragged.
  assert.equal(bottom.index, 5);
  // Nothing to scroll.
  const none = Herdr.visibleWindow(0, 20, 0, 3);
  assert.equal(none.text, "");
  assert.equal(none.total, 0);
  assert.equal(Herdr.visibleWindow(0, 0, 5, 0).text, "");
});

test("the footer says which way there is more", () => {
  assert.equal(Herdr.footerHint({ above: 2, below: 3, total: 7 }), "2 above · 3 below");
  assert.equal(Herdr.footerHint({ above: 2, below: 0, total: 7 }), "2 above");
  assert.equal(Herdr.footerHint({ above: 0, below: 3, total: 7 }), "3 below");
  assert.equal(Herdr.footerHint({ above: 0, below: 0, total: 7 }), "");
  assert.equal(Herdr.footerHint(null), "");
  assert.equal(Herdr.footerHint({ total: 0 }), "");
});

test("row height follows the tile, so a long list still fits", () => {
  assert.ok(Herdr.rowHeight(300) > Herdr.rowHeight(180));
  assert.ok(Herdr.rowHeight(300) >= 20);
  assert.ok(Herdr.rowHeight(1) >= 20);
  assert.ok(Herdr.rowHeight("bad") >= 20);
  assert.equal(Herdr.twoLine(300), true);
  assert.equal(Herdr.twoLine(200), false);
  assert.equal(Herdr.twoLine("bad"), false);
});

test("the placeholder says which kind of nothing it is", () => {
  assert.equal(Herdr.emptyHeadline({ error: "no herdr server" }), "Herdr is not answering");
  assert.equal(Herdr.emptyBody({ error: "no herdr server" }), "no herdr server");
  assert.equal(Herdr.emptyHeadline({ total: 0, busyOnly: true }), "Nothing running");
  assert.equal(Herdr.emptyBody({ total: 0, busyOnly: true }), "No agent is working or blocked here.");
  // A section with no agents is not an empty session, and says which it is.
  assert.equal(Herdr.emptyHeadline({ total: 0, hidden: 2 }), "Nothing here");
  assert.equal(Herdr.emptyBody({ total: 0, hidden: 2 }), "This section has no agents in it.");
  // The busy filter explains itself even when agents are being left out.
  assert.equal(Herdr.emptyHeadline({ total: 0, hidden: 3, busyOnly: true }), "Nothing running");
  // An empty session, unfiltered, points at Herdr itself.
  assert.equal(Herdr.emptyHeadline({ total: 0, hidden: 0 }), "No agents");
  assert.equal(Herdr.emptyHeadline({}), "No agents");
  assert.equal(Herdr.emptyBody({}), "Start an agent in Herdr.");
  assert.equal(Herdr.emptyHeadline({ total: 0 }), "No agents");
  assert.equal(Herdr.emptyBody({ total: 0 }), "Start an agent in Herdr.");
});

test("the footer names the section it is watching", () => {
  assert.equal(Herdr.sectionLabel({ sectionLabel: "tab 2" }), "tab 2");
  assert.equal(Herdr.sectionLabel({}), "All sections");
  assert.equal(Herdr.sectionLabel(null), "All sections");
  assert.equal(Herdr.versionLabel({ version: "0.8.2" }), "v0.8.2");
  assert.equal(Herdr.versionLabel({}), "");
});
