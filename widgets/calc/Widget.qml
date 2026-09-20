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

  function press(key) {
    if (key === "C") { root.expr = ""; root.display = "0"; return }
    if (key === "=") {
      var value = parseExpr(tokenize(root.expr))
      if (value === null || !isFinite(value)) { root.display = "Err"; return }
      root.display = String(Math.round(value * 1000000) / 1000000)
      root.expr = root.display
      return
    }
    if (root.display === "Err") { root.expr = ""; root.display = "0" }
    var next = root.expr + key
    root.expr = next
    root.display = next
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(5)
    spacing: Style.space(3)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.display
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideLeft
      horizontalAlignment: Text.AlignRight
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.host && root.host.launchDefault) root.host.launchDefault()
      }
    }

    Grid {
      width: parent.width
      height: parent.height - Style.space(28)
      columns: 4
      rows: 4
      columnSpacing: Style.space(2)
      rowSpacing: Style.space(2)

      Repeater {
        model: ["7","8","9","/","4","5","6","*","1","2","3","-","C","0","=","+"]

        Rectangle {
          required property string modelData
          width: Math.floor((parent.width - Style.space(6)) / 4)
          height: Math.floor((parent.height - Style.space(6)) / 4)
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, keyMouse.containsMouse ? 0.22 : 0.12)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData === "*" ? "×" : (modelData === "/" ? "÷" : modelData)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
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
