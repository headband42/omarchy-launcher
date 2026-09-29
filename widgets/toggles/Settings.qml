import QtQuick
import qs.Commons
import qs.Ui
import "toggles.js" as Toggles

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

  readonly property var rows: Toggles.ROWS
  readonly property var picked: Toggles.rowsFromSettings(root.settings)

  implicitWidth: Style.space(300)
  implicitHeight: Style.space(40) * (root.rows.length + 1) + Style.space(24)

  function has(id) {
    for (var i = 0; i < root.picked.length; i++) {
      if (root.picked[i].id === id) return true
    }
    return false
  }

  function toggle(id) {
    // Keep at least one row, or the tile has nothing to show.
    if (root.has(id) && root.picked.length <= 1) return
    var ids = []
    for (var i = 0; i < root.picked.length; i++) ids.push(root.picked[i].id)
    var next = []
    for (var j = 0; j < ids.length; j++) {
      if (ids[j] !== id) next.push(ids[j])
    }
    if (next.length === ids.length) next.push(id)
    root.settings = Toggles.settingsFromRows(next)
    root.forceActiveFocus()
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Up) {
      root.selectedIndex = (root.selectedIndex - 1 + root.rows.length) % root.rows.length
      return true
    }
    if (event.key === Qt.Key_Down) {
      root.selectedIndex = (root.selectedIndex + 1) % root.rows.length
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.toggle(root.rows[root.selectedIndex].id)
      return true
    }
    return false
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Show these switches on the tile"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Repeater {
      model: root.rows

      BorderSurface {
        required property var modelData
        required property int index
        width: parent.width
        height: Style.space(40)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            y: Math.max(0, (parent.height - height) / 2)
            textFormat: Text.PlainText
            text: modelData.glyph
            color: root.foreground
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width - Style.space(8) * 2 - Style.space(16)
            y: Math.max(0, (parent.height - height) / 2)
            textFormat: Text.PlainText
            text: modelData.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            y: Math.max(0, (parent.height - height) / 2)
            textFormat: Text.PlainText
            text: "󰄬"
            color: Color.accent
            opacity: root.has(modelData.id) ? 1 : 0
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: {
            root.selectedIndex = index
            root.toggle(modelData.id)
          }
        }
      }
    }
  }
}
