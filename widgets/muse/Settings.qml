import QtQuick
import qs.Commons
import qs.Ui
import "../_kit"

// Which Muse quota blocks the tile shows, and how resets read. The numbers
// come from the sign-in Muse already has, polled on a timer.
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

  readonly property var limits: [
    { id: "window", label: "5-hour window", note: "The current window's quota" },
    { id: "weekly", label: "Week", note: "The rolling week's quota" }
  ]
  // The limits, then the reset style.
  readonly property int rowCount: root.limits.length + 1

  implicitWidth: Style.space(360)
  implicitHeight: body.implicitHeight

  function isHidden(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    return list.indexOf(String(id)) >= 0
  }

  function commit(hidden, style) {
    var next = {}
    if (hidden) next.hidden = String(hidden)
    if (style === "absolute") next.resetStyle = "absolute"
    // An empty object forgets the settings: every block, counted down.
    root.settings = next
    root.forceActiveFocus()
  }

  function toggleLimit(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    var at = list.indexOf(String(id))
    if (at >= 0) list.splice(at, 1)
    else list.push(String(id))
    root.commit(list.join(","), root.resetStyle)
  }

  function toggleStyle() {
    root.commit(root.hidden, root.resetStyle === "relative" ? "absolute" : "relative")
  }

  function activate(index) {
    root.selectedIndex = index
    if (index < root.limits.length) root.toggleLimit(root.limits[index].id)
    else root.toggleStyle()
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
      root.commit("", root.resetStyle)
      return true
    }
    if (event.key === Qt.Key_Space) {
      root.toggleStyle()
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
      text: "Read from the sign-in Muse already has. Hide a block to leave it off the tile. Enter switches the selected row, Space the reset style, and Delete shows every block again."
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.limits

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
      selected: root.selectedIndex === root.limits.length
      title: "Reset style"
      note: root.resetStyle === "absolute" ? "The day and time a block frees up" : "How long until a block frees up"
      tag: root.resetStyle === "absolute" ? "day" : "countdown"
      lit: true
      hoverFill: root.hoverFill
      selectedBorder: root.borderSpec
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      foreground: root.foreground
      onHovered: root.selectedIndex = root.limits.length
      onPicked: root.activate(root.limits.length)
    }
  }
}
