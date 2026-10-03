#!/usr/bin/env node
// Logic tests for the mail tile. Stdlib only.
//
// Run from the repo root:  node --test widgets/mail/test_logic.cjs

process.env.TZ = "America/Denver";

const test = require("node:test");
const assert = require("node:assert/strict");
const M = require("./mail.js");

// Friday 2 October 2026, 08:30 in Denver.
const NOW = new Date(2026, 9, 2, 8, 30).getTime() / 1000;

const gmail = {
  id: "a1", name: "ada@gmail.com", address: "ada@gmail.com", providerName: "Gmail", view: "primary",
  ok: true, unread: 5, uidvalidity: 7, web: "https://mail.google.com/mail/u/?authuser=ada%40gmail.com",
  messages: [
    { uid: 9, from: "Bob", subject: "Lunch", date: NOW - 120, link: "https://mail.google.com/mail/u/?authuser=ada%40gmail.com#inbox/ff" },
    { uid: 5, from: "Jürgen", subject: "Grüße", date: NOW - 7200, link: "" },
  ],
};
const work = {
  id: "b2", name: "me@work.example", address: "me@work.example", providerName: "Mail", view: "inbox",
  ok: false, state: "auth", error: "Wrong address or app password", stale: true, unread: 1, uidvalidity: 3, web: "",
  messages: [{ uid: 4, from: "Boss", subject: "Hi", date: NOW - 86400 * 3 }],
};

test("ages: minutes, hours, the weekday, then the date", () => {
  assert.equal(M.fmtAge(NOW, NOW - 20), "now");
  assert.equal(M.fmtAge(NOW, NOW - 600), "10m");
  assert.equal(M.fmtAge(NOW, NOW - 3 * 3600), "3h");
  assert.equal(M.fmtAge(NOW, NOW - 3 * 86400), "Tue");
  assert.equal(M.fmtAge(NOW, new Date(2026, 8, 20, 9).getTime() / 1000), "Sep 20");
  assert.equal(M.fmtAge(NOW, new Date(2025, 11, 24, 9).getTime() / 1000), "Dec 24 2025");
  assert.equal(M.fmtAge(NOW, 0), "");
});

test("one healthy account: messages, then what did not fit", () => {
  const rows = M.rows({ ok: true, accounts: [gmail] }, {});
  assert.deepEqual(rows.map((r) => r.kind), ["message", "message", "more"]);
  assert.equal(rows[2].count, 3);
  assert.equal(rows[0].canRead, true);
  assert.equal(M.title({ accounts: [gmail] }), "GMAIL");
  assert.equal(M.unreadLabel(M.totalUnread({ accounts: [gmail] }, {})), "5 unread");
});

test("several accounts get a row each, and a failing one says why", () => {
  const rows = M.rows({ ok: true, accounts: [gmail, work] }, {});
  assert.deepEqual(rows.map((r) => r.kind), ["account", "message", "message", "more", "account", "message"]);
  assert.equal(rows[4].error, "Wrong address or app password");
  assert.equal(rows[5].canRead, false);
  assert.equal(M.title({ accounts: [gmail, work] }), "MAIL");
  assert.equal(M.title({ accounts: [gmail, { ...gmail, id: "c3" }] }), "GMAIL");
});

test("a lone failing account with old mail heads it with the problem", () => {
  const rows = M.rows({ ok: true, accounts: [work] }, {});
  assert.deepEqual(rows.map((r) => r.kind), ["account", "message"]);
  const empty = M.rows({ ok: true, accounts: [{ ...work, messages: [], unread: 0 }] }, {});
  assert.deepEqual(empty, []);
  assert.equal(M.emptyText({ ok: true, accounts: [{ ...work, messages: [] }] }), "Wrong address or app password");
  assert.equal(M.emptyGlyph({ ok: true, accounts: [work] }), "󰀦");
});

test("marking read hides the row and takes it off the count", () => {
  const hidden = { [M.hiddenKey("a1", 9)]: true };
  const rows = M.rows({ ok: true, accounts: [gmail] }, hidden);
  assert.deepEqual(rows.filter((r) => r.kind === "message").map((r) => r.message.uid), [5]);
  assert.equal(M.totalUnread({ accounts: [gmail] }, hidden), 4);
  assert.equal(rows.find((r) => r.kind === "more").count, 3);
});

test("a row opens its conversation, else the webmail", () => {
  const rows = M.rows({ ok: true, accounts: [gmail] }, {});
  assert.match(M.target(rows[0]), /#inbox\/ff$/);
  assert.equal(M.target(rows[1]), gmail.web);
  assert.equal(M.target(rows[2]), gmail.web);
  assert.equal(M.target(null), "");
});

test("empty states", () => {
  assert.equal(M.emptyText(null), "Loading…");
  assert.equal(M.emptyText({ ok: true, accounts: [] }), "Add a mail account with the gear");
  assert.equal(M.emptyText({ ok: true, accounts: [{ ...gmail, unread: 0, messages: [] }] }), "Nothing new in Primary");
  assert.equal(M.emptyText({ ok: true, accounts: [{ ...gmail, view: "inbox", unread: 0, messages: [] }] }), "No unread mail");
  assert.equal(M.emptyGlyph({ ok: true, accounts: [{ ...gmail, messages: [] }] }), "󰄬");
});

test("the dot pulses for mail from the last ten minutes", () => {
  assert.equal(M.fresh({ accounts: [gmail] }, {}, NOW), true);
  assert.equal(M.fresh({ accounts: [gmail] }, { [M.hiddenKey("a1", 9)]: true }, NOW), false);
});

test("views cycle", () => {
  assert.equal(M.nextView("primary"), "inbox");
  assert.equal(M.nextView("important"), "primary");
  assert.equal(M.viewLabel("important"), "Important");
});

test("the cache is used only when it holds accounts", () => {
  assert.equal(M.fromCache("not json"), null);
  assert.equal(M.fromCache(JSON.stringify({ ok: true, accounts: [] })), null);
  assert.equal(M.fromCache(JSON.stringify({ ok: true, accounts: [gmail] })).accounts.length, 1);
});
