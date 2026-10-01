// Calculator core for the calc tile. QML imports this file; node tests require it.
// keyText reads Qt key constants, so a test sets a global Qt before calling it.

function tokenize(input) {
  var s = String(input || "").replace(/\s+/g, "")
  var out = []
  var i = 0
  while (i < s.length) {
    var ch = s.charAt(i)
    if ("+-*/".indexOf(ch) >= 0) { out.push({ kind: "op", value: ch }); i++; continue }
    if (ch === "(" || ch === ")") { out.push({ kind: ch, value: ch }); i++; continue }
    if ((ch >= "0" && ch <= "9") || ch === ".") {
      var j = i + 1
      while (j < s.length && ((s.charAt(j) >= "0" && s.charAt(j) <= "9") || s.charAt(j) === ".")) j++
      out.push({ kind: "num", value: parseFloat(s.slice(i, j)) })
      i = j
      continue
    }
    return null
  }
  return out
}

function parseExpr(tokens) {
  if (!tokens) return null
  var i = 0
  function peek() { return tokens[i] || null }
  function take() { return tokens[i++] || null }
  function parseFactor() {
    var t = peek()
    if (!t) return null
    if (t.kind === "num") { take(); return t.value }
    if (t.kind === "op" && t.value === "-") { take(); var v = parseFactor(); return v === null ? null : -v }
    if (t.kind === "(") {
      take()
      var inner = parseAdd()
      if (!peek() || peek().kind !== ")") return null
      take()
      return inner
    }
    return null
  }
  function parseMul() {
    var v = parseFactor()
    if (v === null) return null
    while (peek() && peek().kind === "op" && (peek().value === "*" || peek().value === "/")) {
      var op = take().value
      var r = parseFactor()
      if (r === null) return null
      v = op === "*" ? v * r : (r === 0 ? null : v / r)
      if (v === null) return null
    }
    return v
  }
  function parseAdd() {
    var v = parseMul()
    if (v === null) return null
    while (peek() && peek().kind === "op" && (peek().value === "+" || peek().value === "-")) {
      var op = take().value
      var r = parseMul()
      if (r === null) return null
      v = op === "+" ? v + r : v - r
    }
    return v
  }
  var result = parseAdd()
  if (result === null || i !== tokens.length) return null
  return result
}

function fmtValue(value) {
  return String(Math.round(value * 1000000) / 1000000)
}

function previewOf(expr) {
  if (!expr) return ""
  var value = parseExpr(tokenize(expr))
  if (value === null || !isFinite(value)) return ""
  return "= " + fmtValue(value)
}

// One key applied to { expr, display, preview }. Returns the next state.
function press(state, key) {
  var expr = String(state.expr || "")
  var display = String(state.display === undefined ? "0" : state.display)
  var preview = String(state.preview || "")
  function done() { return { expr: expr, display: display, preview: preview } }

  if (key === "C") { expr = ""; display = "0"; preview = ""; return done() }
  if (key === "←") {
    if (display === "Err" || !expr) { expr = ""; display = "0" }
    else { expr = expr.slice(0, -1); display = expr || "0" }
    preview = previewOf(expr)
    return done()
  }
  if (key === "=") {
    var value = parseExpr(tokenize(expr))
    if (value === null || !isFinite(value)) { display = "Err"; preview = ""; return done() }
    display = fmtValue(value)
    expr = display
    preview = ""
    return done()
  }
  if (display === "Err") { expr = ""; display = "0"; preview = "" }
  if (key === ".") {
    var tail = expr.split(/[\+\-\*\/()]/).pop()
    if (tail.indexOf(".") >= 0) return done()
  }
  expr += key
  display = expr
  preview = previewOf(expr)
  return done()
}

// Derive a calc character from a key event without trusting event.text,
// which Wayland/X11 don't always provide for pad keys.
function keyText(key, modifiers, text) {
  if (text === ",") text = "."
  if (text.length === 1) return text
  if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
  if (modifiers & Qt.KeypadModifier) {
    switch (key) {
      case Qt.Key_Slash: return "/"
      case Qt.Key_Asterisk: return "*"
      case Qt.Key_Minus: return "-"
      case Qt.Key_Plus: return "+"
      case Qt.Key_Period: return "."
    }
  }
  return ""
}

if (typeof module !== "undefined") {
  module.exports = { tokenize: tokenize, parseExpr: parseExpr, previewOf: previewOf, press: press, keyText: keyText }
}
