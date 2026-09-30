function parse(text) {
  var rows = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "")
    if (!line.trim()) continue
    var done = false
    var body = line.trim()
    if (body.slice(0, 4).toLowerCase() === "[x] ") {
      done = true
      body = body.slice(4)
    } else if (body.slice(0, 4).toLowerCase() === "[ ] ") {
      body = body.slice(4)
    }
    rows.push({ text: body.trim(), done: done })
  }
  return rows
}

function format(rows) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var row = rows[i] || {}
    var text = String(row.text || "").trim()
    if (!text) continue
    out.push(row.done ? "[x] " + text : "[ ] " + text)
  }
  return out.length > 0 ? out.join("\n") + "\n" : ""
}

function copy(rows) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var row = rows[i] || {}
    out.push({ text: String(row.text || ""), done: !!row.done })
  }
  return out
}

function toggle(rows, index) {
  var out = copy(rows)
  if (index < 0 || index >= out.length) return out
  out[index].done = !out[index].done
  return out
}

// New items land on top so the tile always shows the newest work.
function add(rows, text) {
  var body = String(text || "").trim()
  if (!body) return copy(rows)
  var out = copy(rows)
  out.unshift({ text: body, done: false })
  return out
}

function remove(rows, index) {
  var out = copy(rows)
  if (index < 0 || index >= out.length) return out
  out.splice(index, 1)
  return out
}

// Visible rows carry their index in the full list so a click still lands.
function visible(rows, showDone) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var row = rows[i] || {}
    if (showDone || !row.done) out.push({ text: String(row.text || ""), done: !!row.done, index: i })
  }
  return out
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
    parse: parse,
    format: format,
    copy: copy,
    toggle: toggle,
    add: add,
    remove: remove,
    visible: visible,
    resolvePath: resolvePath,
    dirOf: dirOf
  }
}
