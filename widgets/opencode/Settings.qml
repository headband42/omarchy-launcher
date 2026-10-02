import QtQuick
import qs.Commons
import qs.Ui
import "../_kit"

// Which Go blocks the tile shows, how resets read, and whether the money
// line is drawn. Everything is a plain option, so it follows the widget.
Item {
  id: root
  focus: true

  property var tile: ({})
  property var settings: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color hoverFill: Color.menu.background
  property var borderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius

  property int selectedIndex: 0

  readonly property string hidden: String((root.settings && root.settings.hidden) || "")
  readonly property string resetStyle: String((root.settings && root.settings.resetStyle) || "relative")
  readonly property bool showAmounts: !(root.settings && root.settings.showAmounts === false)

  readonly property var blocks: [
    { id: "fiveHour", label: "5-hour block", note: "A rolling window that starts with a request" },
    { id: "week", label: "Weekly block", note: "Resets every week" },
    { id: "month", label: "Monthly block", note: "Resets with the plan" }
  ]
  // The three blocks, then the reset style, then the money line.
  readonly property int rowCount: root.blocks.length + 2

  implicitWidth: Style.space(360)
  implicitHeight: body.implicitHeight

  function isHidden(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    return list.indexOf(String(id)) >= 0
  }

  function commit(hidden, style, amounts) {
    root.settings = { hidden: String(hidden || ""), resetStyle: String(style || "relative"), showAmounts: amounts !== false }
    root.forceActiveFocus()
  }

  function toggleBlock(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    var at = list.indexOf(String(id))
    if (at >= 0) list.splice(at, 1)
    else list.push(String(id))
    root.commit(list.join(","), root.resetStyle, root.showAmounts)
  }

  function toggleStyle() {
    root.commit(root.hidden, root.resetStyle === "relative" ? "absolute" : "relative", root.showAmounts)
  }

  function toggleAmounts() {
    root.commit(root.hidden, root.resetStyle, !root.showAmounts)
  }

  function activate(index) {
    root.selectedIndex = index
    if (index < root.blocks.length) root.toggleBlock(root.blocks[index].id)
    else if (index === root.blocks.length) root.toggleStyle()
    else root.toggleAmounts()
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Up) {
      root.selectedIndex = (root.selectedIndex - 1 + root.rowCount) % root.rowCount
      return true
    }
    if (event.key === Qt.Key_Down) {
      root.selectedIndex = (root.selectedIndex + 1) % root.rowCount
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activate(root.selectedIndex)
      return true
    }
    if (event.key === Qt.Key_Delete) {
      root.commit("", root.resetStyle, root.showAmounts)
      return true
    }
    if (event.key === Qt.Key_Space) {
      root.toggleStyle()
      return true
    }
    if (event.key === Qt.Key_A) {
      root.toggleAmounts()
      return true
    }
    return false
  }

  Component.onCompleted: root.forceActiveFocus()

  Column {
    id: body
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      bottomPadding: Style.space(6)
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Go limits each model over three blocks. Hide one to leave it off the tile. Enter switches the selected row, Space the reset style, A the money line, and Delete shows every block again."
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.blocks

      OptionRow {
        required property var modelData
        required property int index
        width: body.width
        selected: index === root.selectedIndex
        title: modelData.label
        note: modelData.note
        tag: root.isHidden(modelData.id) ? "hidden" : "shown"
        lit: !root.isHidden(modelData.id)
        hoverFill: root.hoverFill
        selectedBorder: root.borderSpec
        cornerRadius: root.cornerRadius
        fontFamily: root.fontFamily
        foreground: root.foreground
        onHovered: root.selectedIndex = index
        onPicked: root.activate(index)
      }
    }

    OptionRow {
      width: body.width
      selected: root.selectedIndex === root.blocks.length
      title: "Reset style"
      note: root.resetStyle === "absolute" ? "The day and time a block frees up" : "How long until a block frees up"
      tag: root.resetStyle === "absolute" ? "day" : "countdown"
      lit: true
      hoverFill: root.hoverFill
      selectedBorder: root.borderSpec
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      foreground: root.foreground
      onHovered: root.selectedIndex = root.blocks.length
      onPicked: root.activate(root.blocks.length)
    }

    OptionRow {
      width: body.width
      selected: root.selectedIndex === root.blocks.length + 1
      title: "Money line"
      note: "What is spent of each block, under its bar"
      tag: root.showAmounts ? "on" : "off"
      lit: root.showAmounts
      hoverFill: root.hoverFill
      selectedBorder: root.borderSpec
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      foreground: root.foreground
      onHovered: root.selectedIndex = root.blocks.length + 1
      onPicked: root.activate(root.blocks.length + 1)
    }
  }
}
