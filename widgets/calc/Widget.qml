import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property string expr: ""
  property string display: "0"
  property string preview: ""

  readonly property var keys: ["C","(",")","/","7","8","9","*","4","5","6","-","1","2","3","+","0",".","←","="]

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

  function updatePreview() {
    if (!root.expr) { root.preview = ""; return }
    var value = parseExpr(tokenize(root.expr))
    if (value === null || !isFinite(value)) { root.preview = ""; return }
    root.preview = "= " + String(Math.round(value * 1000000) / 1000000)
  }

  function press(key) {
    if (key === "C") { root.expr = ""; root.display = "0"; root.preview = ""; return }
    if (key === "←") {
      if (root.display === "Err" || !root.expr) { root.expr = ""; root.display = "0" }
      else { root.expr = root.expr.slice(0, -1); root.display = root.expr || "0" }
      updatePreview()
      return
    }
    if (key === "=") {
      var value = parseExpr(tokenize(root.expr))
      if (value === null || !isFinite(value)) { root.display = "Err"; root.preview = ""; return }
      root.display = String(Math.round(value * 1000000) / 1000000)
      root.expr = root.display
      root.preview = ""
      return
    }
    if (root.display === "Err") { root.expr = ""; root.display = "0"; root.preview = "" }
    if (key === ".") {
      var tail = root.expr.split(/[\+\-\*\/()]/).pop()
      if (tail.indexOf(".") >= 0) return
    }
    root.expr += key
    root.display = root.expr
    updatePreview()
  }

  function keyFill(key, hot) {
    if (key === "=") return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, hot ? 0.55 : 0.38)
    if (key === "C") return Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, hot ? 0.42 : 0.22)
    if (key === "←") return Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, hot ? 0.30 : 0.13)
    if ("+-*/".indexOf(key) >= 0) return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hot ? 0.22 : 0.10)
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, hot ? 0.20 : 0.08)
  }

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(12)

    Rectangle {
      id: displayBox
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Math.max(Style.space(40), Math.round(parent.height * 0.28))
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(12)
        spacing: 1

        Text {
          width: parent.width - Style.space(24)
          x: Style.space(12)
          textFormat: Text.PlainText
          text: root.display
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.Medium
          elide: Text.ElideLeft
          horizontalAlignment: Text.AlignRight
        }

        Text {
          visible: root.preview.length > 0
          width: parent.width - Style.space(24)
          x: Style.space(12)
          textFormat: Text.PlainText
          text: root.preview
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideLeft
          horizontalAlignment: Text.AlignRight
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.host && root.host.launchDefault) root.host.launchDefault()
      }
    }

    Grid {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: displayBox.bottom
      anchors.topMargin: Style.space(10)
      anchors.bottom: parent.bottom
      columns: 4
      rows: 5
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(6)

      Repeater {
        model: root.keys

        Rectangle {
          required property string modelData
          width: Math.floor((parent.width - parent.columnSpacing * 3) / 4)
          height: Math.floor((parent.height - parent.rowSpacing * 4) / 5)
          radius: Math.max(4, Style.cornerRadius)
          color: root.keyFill(modelData, keyMouse.containsMouse)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData === "*" ? "×" : (modelData === "/" ? "÷" : modelData)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: (modelData === "=" || modelData === "C" || modelData === "←") ? Font.DemiBold : Font.Normal
          }

          MouseArea {
            id: keyMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.press(modelData)
          }
        }
      }
    }
  }
}
