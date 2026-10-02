// Pure helpers for the todo widget. QML imports this file; node tests require it.
//
// The file is kept line by line. In a Markdown file only checkbox lines
// ("- [ ] x", "  1. [x] y") are tasks, and every other line (headings, notes,
// blanks) is written back exactly as it was. Any other file is a plain list:
// each line is a task except blanks and "# " headings, and a save gives every
// task a box.

var TASK_RE = /^(\s*)((?:[-*+]|\d+[.)])\s+)?\[( |x|X)\](?:\s(.*))?$/
var BULLET_RE = /^(\s*)((?:[-*+]|\d+[.)])\s+)?(.*)$/
var HEADING_RE = /^\s*#{1,6}\s/
var MARKDOWN_RE = /\.(md|markdown|mdown|mkd)$/i

function isMarkdown(path) {
  return MARKDOWN_RE.test(String(path || ""))
}

function textLine(raw) {
  return { task: false, raw: String(raw), indent: "", bullet: "", done: false, text: "" }
}

function taskLine(indent, bullet, done, text) {
  return { task: true, raw: "", indent: String(indent || ""), bullet: String(bullet || ""), done: !!done, text: String(text || "").trim() }
}

function parse(text, markdown) {
  var lines = String(text || "").split("\n")
  if (lines.length && lines[lines.length - 1] === "") lines.pop()
  var out = []
  for (var j = 0; j < lines.length; j++) {
    var line = lines[j].replace(/\r$/, "")
    var match = TASK_RE.exec(line)
    if (match) {
      out.push(taskLine(match[1], match[2], match[3] !== " ", match[4]))
    } else if (!markdown && line.trim() && !HEADING_RE.test(line)) {
      var plain = BULLET_RE.exec(line)
      out.push(taskLine(plain[1], plain[2], false, plain[3]))
    } else {
      out.push(textLine(line))
    }
  }
  return out
}

function format(lines) {
  var out = []
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i] || {}
    if (!line.task) {
      out.push(String(line.raw || ""))
      continue
    }
    var text = String(line.text || "").trim()
    if (!text) continue
    out.push(String(line.indent || "") + String(line.bullet || "") + (line.done ? "[x] " : "[ ] ") + text)
  }
  // Blank lines at the end are not worth keeping.
  while (out.length && !out[out.length - 1].trim()) out.pop()
  return out.length ? out.join("\n") + "\n" : ""
}

function copy(lines) {
  var out = []
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i] || {}
    out.push(line.task ? taskLine(line.indent, line.bullet, line.done, line.text) : textLine(line.raw || ""))
  }
  return out
}

function isTask(lines, index) {
  return index >= 0 && index < (lines || []).length && !!(lines[index] && lines[index].task)
}

function toggle(lines, index) {
  var out = copy(lines)
  if (isTask(out, index)) out[index].done = !out[index].done
  return out
}

function rename(lines, index, text) {
  var out = copy(lines)
  var body = String(text || "").trim()
  if (isTask(out, index) && body) out[index].text = body
  return out
}

function remove(lines, index) {
  var out = copy(lines)
  if (isTask(out, index)) out.splice(index, 1)
  return out
}

// New tasks land above the first task, styled like it, so the newest work
// is on top. With no task yet, under a leading heading, as a Markdown list
// item in a Markdown file.
function add(lines, text, markdown) {
  var body = String(text || "").trim()
  var out = copy(lines)
  if (!body) return out
  for (var i = 0; i < out.length; i++) {
    if (out[i].task) {
      out.splice(i, 0, taskLine(out[i].indent, out[i].bullet, false, body))
      return out
    }
  }
  var at = 0
  if (out.length && HEADING_RE.test(out[0].raw)) {
    at = 1
    if (out.length > 1 && !out[1].raw.trim()) at = 2
  }
  out.splice(at, 0, taskLine("", markdown ? "- " : "", false, body))
  return out
}

function clearDone(lines) {
  var out = []
  var all = copy(lines)
  for (var i = 0; i < all.length; i++) if (!(all[i].task && all[i].done)) out.push(all[i])
  return out
}

function counts(lines) {
  var open = 0
  var done = 0
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i] || {}
    if (!line.task) continue
    if (line.done) done++
    else open++
  }
  return { open: open, done: done, total: open + done }
}

function indentWidth(indent) {
  return String(indent || "").replace(/\t/g, "  ").length
}

// Nesting by rank of indent width, so two-space and four-space files read alike.
function depths(lines) {
  var widths = []
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i] || {}
    if (!line.task) continue
    var w = indentWidth(line.indent)
    if (widths.indexOf(w) < 0) widths.push(w)
  }
  widths.sort(function(a, b) { return a - b })
  var out = {}
  for (var j = 0; j < (lines || []).length; j++) {
    if (lines[j] && lines[j].task) out[j] = Math.min(3, widths.indexOf(indentWidth(lines[j].indent)))
  }
  return out
}

// The rows the tile draws, in file order. Finished tasks show when asked
// to, or for a moment after they are ticked (`linger` holds their indices).
function visible(lines, showDone, linger) {
  var out = []
  var keep = linger || {}
  var depth = depths(lines)
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i] || {}
    if (!line.task) continue
    if (line.done && !showDone && !keep[i]) continue
    out.push({ text: String(line.text || ""), done: !!line.done, index: i, depth: depth[i] || 0 })
  }
  return out
}

// "2 left", "all done", or "" for an empty list.
function summary(lines) {
  var c = counts(lines)
  if (!c.total) return ""
  if (!c.open) return "all done"
  return c.open + " left"
}

function progress(lines) {
  var c = counts(lines)
  return c.total ? c.done / c.total : 0
}

function resolvePath(raw, home) {
  var value = String(raw || "").trim()
  if (!value) return String(home || "") + "/.local/share/ande.launcher/todo.txt"
  if (value.charAt(0) === "~") return String(home || "") + value.slice(1)
  return value
}

function dirOf(path) {
  var value = String(path || "")
  var cut = value.lastIndexOf("/")
  return cut > 0 ? value.slice(0, cut) : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    isMarkdown: isMarkdown,
    parse: parse,
    format: format,
    copy: copy,
    toggle: toggle,
    rename: rename,
    add: add,
    remove: remove,
    clearDone: clearDone,
    counts: counts,
    depths: depths,
    visible: visible,
    summary: summary,
    progress: progress,
    resolvePath: resolvePath,
    dirOf: dirOf
  }
}
