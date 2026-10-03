import QtQuick
import qs.Commons
import qs.Ui
import "../_kit"

// Which Muse rows the tile shows. The numbers come from Muse Code's
// session logs on this machine, so there is nothing to sign in to.
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

  readonly property var rows: [
    { id: "context", label: "Context", note: "How full the latest call's context window was" },
    { id: "today", label: "Today", note: "Tokens since midnight, local time" },
    { id: "week", label: "7 days", note: "Tokens in the last seven days" }
  ]
  readonly property int rowCount: root.rows.length

  implicitWidth: Style.space(360)
  implicitHeight: body.implicitHeight

  function isHidden(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    return list.indexOf(String(id)) >= 0
  }

  function commit(hidden) {
    var next = {}
    if (hidden) next.hidden = String(hidden)
    // An empty object forgets the settings: every row again.
    root.settings = next
    root.forceActiveFocus()
  }

  function toggleRow(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    var at = list.indexOf(String(id))
    if (at >= 0) list.splice(at, 1)
    else list.push(String(id))
    root.commit(list.join(","))
  }

  function activate(index) {
    root.selectedIndex = index
    root.toggleRow(root.rows[index].id)
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
      root.commit("")
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
      text: "Read from Muse Code's session logs on this machine. Hide a row to leave it off the tile. Enter switches the selected row, and Delete shows every row again."
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.rows

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
  }
}
