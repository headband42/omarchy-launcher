#!/usr/bin/env node
// Logic tests for the todo widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/todo/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Todo = require("./todo.js");

test("parses lines into rows", () => {
  assert.deepEqual(Todo.parse("[ ] buy milk\n[x] done thing\n\n  \nwrite code\n"),
                   [{ text: "buy milk", done: false },
                    { text: "done thing", done: true },
                    { text: "write code", done: false }]);
  assert.deepEqual(Todo.parse("[X] uppercase done\n"), [{ text: "uppercase done", done: true }]);
  assert.deepEqual(Todo.parse(""), []);
  assert.deepEqual(Todo.parse(null), []);
  assert.deepEqual(Todo.parse("\n\n"), []);
});

test("formats rows back to text", () => {
  assert.equal(Todo.format([{ text: "buy milk", done: false },
                            { text: "done thing", done: true }]),
               "[ ] buy milk\n[x] done thing\n");
  assert.equal(Todo.format([]), "");
  assert.equal(Todo.format([{ text: "  ", done: true }]), "");
});

test("round-trips through format and parse", () => {
  const rows = [{ text: "one", done: true }, { text: "two", done: false },
                { text: "x not a marker", done: false }, { text: "[x] also text", done: true }];
  assert.deepEqual(Todo.parse(Todo.format(rows)), rows);
});

test("toggles by index", () => {
  const rows = [{ text: "one", done: false }, { text: "two", done: true }];
  assert.deepEqual(Todo.toggle(rows, 0), [{ text: "one", done: true }, { text: "two", done: true }]);
  assert.deepEqual(Todo.toggle(rows, 1), [{ text: "one", done: false }, { text: "two", done: false }]);
  assert.deepEqual(Todo.toggle(rows, 9), rows);
  assert.equal(Todo.toggle(rows, 0)[0] === rows[0], false);
  assert.equal(rows[0].done, false);
});

test("adds to the top and ignores blanks", () => {
  const rows = [{ text: "old", done: false }];
  assert.deepEqual(Todo.add(rows, "  new task  "), [{ text: "new task", done: false }, { text: "old", done: false }]);
  assert.deepEqual(Todo.add(rows, "   "), rows);
  assert.deepEqual(Todo.add(rows, null), rows);
});

test("removes by index", () => {
  const rows = [{ text: "one", done: false }, { text: "two", done: true }];
  assert.deepEqual(Todo.remove(rows, 0), [{ text: "two", done: true }]);
  assert.deepEqual(Todo.remove(rows, 1), [{ text: "one", done: false }]);
  assert.deepEqual(Todo.remove(rows, 9), rows);
});

test("filters visible rows and keeps full indices", () => {
  const rows = [{ text: "one", done: true }, { text: "two", done: false }, { text: "three", done: false }];
  assert.deepEqual(Todo.visible(rows, false),
                   [{ text: "two", done: false, index: 1 }, { text: "three", done: false, index: 2 }]);
  assert.deepEqual(Todo.visible(rows, true),
                   [{ text: "one", done: true, index: 0 }, { text: "two", done: false, index: 1 },
                    { text: "three", done: false, index: 2 }]);
});

test("resolves paths", () => {
  assert.equal(Todo.resolvePath("", "/home/u"), "/home/u/.local/share/ande.launcher/todo.txt");
  assert.equal(Todo.resolvePath("   ", "/home/u"), "/home/u/.local/share/ande.launcher/todo.txt");
  assert.equal(Todo.resolvePath("~/notes/todo.txt", "/home/u"), "/home/u/notes/todo.txt");
  assert.equal(Todo.resolvePath("/srv/todo.txt", "/home/u"), "/srv/todo.txt");
  assert.equal(Todo.dirOf("/home/u/notes/todo.txt"), "/home/u/notes");
  assert.equal(Todo.dirOf("todo.txt"), "");
});

test("copies rows without aliasing", () => {
  const rows = [{ text: "one", done: false }];
  const next = Todo.copy(rows);
  next[0].done = true;
  assert.equal(rows[0].done, false);
});
