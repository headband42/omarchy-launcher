#!/usr/bin/env node
// Logic tests for the todo widget. Stdlib only.
//
// Run from the repo root:  node --test widgets/todo/test_logic.cjs

const test = require("node:test");
const assert = require("node:assert/strict");
const Todo = require("./todo.js");

const DOC = `# This week

- [ ] Renew the passport
- [x] Book the dentist
- [ ] Ship the widgets
  - [x] Repo tile
  - [ ] Docker tile
Notes that are not tasks.
1. [ ] Numbered too
`;

function tasks(lines) {
  return lines.filter((l) => l.task).map((l) => [l.text, l.done]);
}

test("knows a Markdown file by its name", () => {
  assert.equal(Todo.isMarkdown("/home/u/notes/todo.md"), true);
  assert.equal(Todo.isMarkdown("/home/u/notes/TODO.Markdown"), true);
  assert.equal(Todo.isMarkdown("/home/u/.local/share/ande.launcher/todo.txt"), false);
  assert.equal(Todo.isMarkdown("/home/u/todo"), false);
  assert.equal(Todo.isMarkdown(null), false);
});

test("reads a plain list as one task per line", () => {
  const lines = Todo.parse("[ ] buy milk\n[x] done thing\n\n  \nwrite code\n");
  // A bare line typed into the file by hand is a task too.
  assert.deepEqual(tasks(lines), [["buy milk", false], ["done thing", true], ["write code", false]]);
  assert.equal(lines[2].task, false);
  const bare = Todo.parse("buy milk\n- call Sam\n# Groceries\n\nwrite code\n");
  assert.deepEqual(tasks(bare), [["buy milk", false], ["call Sam", false], ["write code", false]]);
  assert.equal(bare[1].bullet, "- ");
  assert.equal(bare[2].task, false);
  assert.deepEqual(Todo.parse("[X] uppercase done\n").map((l) => l.done), [true]);
  assert.deepEqual(Todo.parse(""), []);
  assert.deepEqual(Todo.parse(null), []);
});

test("reads a Markdown file's checkboxes and nothing else", () => {
  const lines = Todo.parse(DOC, true);
  assert.deepEqual(tasks(lines), [
    ["Renew the passport", false], ["Book the dentist", true], ["Ship the widgets", false],
    ["Repo tile", true], ["Docker tile", false], ["Numbered too", false]]);
  assert.equal(lines[0].task, false);
  assert.equal(lines[7].raw, "Notes that are not tasks.");
  assert.equal(lines[5].indent, "  ");
  assert.equal(lines[8].bullet, "1. ");
});

test("writes a Markdown file back exactly as it was", () => {
  assert.equal(Todo.format(Todo.parse(DOC, true)), DOC);
  const crlf = "# T\r\n- [ ] one\r\n";
  assert.equal(Todo.format(Todo.parse(crlf, true)), "# T\n- [ ] one\n");
  // The same file as a plain list: the note becomes a task, the heading stays.
  const plain = Todo.parse(DOC, false);
  assert.equal(plain[0].task, false);
  assert.equal(plain[7].task, true);
});

test("gives a plain list its boxes on save", () => {
  assert.equal(Todo.format(Todo.parse("buy milk\n- call Sam\n")), "[ ] buy milk\n- [ ] call Sam\n");
  assert.equal(Todo.format([]), "");
  assert.equal(Todo.format(Todo.parse("[x]\n")), "");
  assert.equal(Todo.format(Todo.parse("[ ] a\n\n\n")), "[ ] a\n");
});

test("keeps a task that looks like a checkbox", () => {
  const lines = Todo.parse("[x] [x] also text\n[ ] x not a marker\n");
  assert.deepEqual(tasks(lines), [["[x] also text", true], ["x not a marker", false]]);
  assert.equal(Todo.format(lines), "[x] [x] also text\n[ ] x not a marker\n");
});

test("toggles one task and leaves the rest alone", () => {
  const lines = Todo.parse(DOC, true);
  const next = Todo.toggle(lines, 2);
  assert.equal(Todo.format(next), DOC.replace("- [ ] Renew", "- [x] Renew"));
  assert.equal(lines[2].done, false);
  assert.equal(Todo.format(Todo.toggle(lines, 0)), DOC);
  assert.equal(Todo.format(Todo.toggle(lines, 99)), DOC);
});

test("renames a task", () => {
  const lines = Todo.parse(DOC, true);
  assert.equal(Todo.format(Todo.rename(lines, 6, "  Docker tile, again ")),
               DOC.replace("  - [ ] Docker tile", "  - [ ] Docker tile, again"));
  assert.equal(Todo.format(Todo.rename(lines, 6, "   ")), DOC);
  assert.equal(Todo.format(Todo.rename(lines, 0, "Heading")), DOC);
});

test("removes a task but never a note", () => {
  const lines = Todo.parse(DOC, true);
  assert.equal(Todo.format(Todo.remove(lines, 3)), DOC.replace("- [x] Book the dentist\n", ""));
  assert.equal(Todo.format(Todo.remove(lines, 7)), DOC);
  assert.equal(Todo.format(Todo.remove(lines, -1)), DOC);
});

test("adds above the first task in its style", () => {
  const lines = Todo.parse(DOC, true);
  assert.equal(Todo.format(Todo.add(lines, "  Water the plants ", true)),
               DOC.replace("- [ ] Renew", "- [ ] Water the plants\n- [ ] Renew"));
  assert.equal(Todo.format(Todo.add([], "first")), "[ ] first\n");
  assert.equal(Todo.format(Todo.add([], "first", true)), "- [ ] first\n");
  // No task yet: under the heading, not above it.
  assert.equal(Todo.format(Todo.add(Todo.parse("# Plans\n\nSome notes.\n", true), "first", true)),
               "# Plans\n\n- [ ] first\nSome notes.\n");
  assert.equal(Todo.format(Todo.add(Todo.parse("# Plans\n"), "first")), "# Plans\n[ ] first\n");
  assert.equal(Todo.format(Todo.add(lines, "   ")), DOC);
  assert.equal(Todo.format(Todo.add(lines, null)), DOC);
});

test("clears finished tasks", () => {
  const cleared = Todo.clearDone(Todo.parse(DOC, true));
  assert.equal(Todo.format(cleared),
               DOC.replace("- [x] Book the dentist\n", "").replace("  - [x] Repo tile\n", ""));
  assert.deepEqual(Todo.counts(cleared), { open: 4, done: 0, total: 4 });
});

test("counts and summarizes", () => {
  const lines = Todo.parse(DOC, true);
  assert.deepEqual(Todo.counts(lines), { open: 4, done: 2, total: 6 });
  assert.equal(Todo.summary(lines), "4 left");
  assert.equal(Todo.summary(Todo.parse("[x] a\n")), "all done");
  assert.equal(Todo.summary([]), "");
  assert.equal(Todo.progress(lines), 2 / 6);
  assert.equal(Todo.progress([]), 0);
});

test("nests by rank of indent", () => {
  const two = Todo.depths(Todo.parse("- [ ] a\n  - [ ] b\n    - [ ] c\n"));
  const four = Todo.depths(Todo.parse("- [ ] a\n    - [ ] b\n\t\t- [ ] c\n"));
  assert.deepEqual(two, { 0: 0, 1: 1, 2: 2 });
  assert.deepEqual(four, { 0: 0, 1: 1, 2: 1 });
});

test("lists the visible rows with their line index", () => {
  const lines = Todo.parse(DOC, true);
  assert.deepEqual(Todo.visible(lines, false).map((r) => [r.index, r.text, r.depth]),
                   [[2, "Renew the passport", 0], [4, "Ship the widgets", 0], [6, "Docker tile", 1], [8, "Numbered too", 0]]);
  assert.equal(Todo.visible(lines, true).length, 6);
  // A task ticked a moment ago stays until the linger ends.
  assert.deepEqual(Todo.visible(lines, false, { 3: true }).map((r) => r.index), [2, 3, 4, 6, 8]);
});

test("resolves paths", () => {
  assert.equal(Todo.resolvePath("", "/home/u"), "/home/u/.local/share/ande.launcher/todo.txt");
  assert.equal(Todo.resolvePath("   ", "/home/u"), "/home/u/.local/share/ande.launcher/todo.txt");
  assert.equal(Todo.resolvePath("~/notes/todo.md", "/home/u"), "/home/u/notes/todo.md");
  assert.equal(Todo.resolvePath("/srv/todo.txt", "/home/u"), "/srv/todo.txt");
  assert.equal(Todo.dirOf("/home/u/notes/todo.txt"), "/home/u/notes");
  assert.equal(Todo.dirOf("todo.txt"), "");
});

test("copies lines without aliasing", () => {
  const lines = Todo.parse("[ ] one\n");
  const next = Todo.copy(lines);
  next[0].done = true;
  assert.equal(lines[0].done, false);
});
