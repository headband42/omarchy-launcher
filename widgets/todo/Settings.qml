import QtQuick
import qs.Commons
import qs.Ui

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

  implicitWidth: Style.space(360)
  implicitHeight: Style.space(180)

  readonly property bool showDone: !!(root.settings && root.settings.showDone)

  function commitPath() {
    var value = String(pathField.text || "").trim()
    var next = {}
    if (value) next.path = value
    if (root.showDone) next.showDone = true
    root.settings = next
    root.forceActiveFocus()
  }

  function toggleShowDone() {
    var next = {}
    var value = String(pathField.text || "").trim()
    if (value) next.path = value
    if (!root.showDone) next.showDone = true
    root.settings = next
    root.forceActiveFocus()
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      if (root.selectedIndex === 0) pathField.forceActiveFocus()
      else root.toggleShowDone()
      return true
    }
    return false
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Checklist file"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    TextField {
      id: pathField
      width: parent.width
      text: String((root.settings && root.settings.path) || "")
      placeholderText: "Empty uses ~/.local/share/ande.launcher/todo.txt"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onEditingFinished: root.commitPath()
      onAccepted: root.commitPath()
    }

    BorderSurface {
      width: parent.width
      height: Style.space(40)
      radius: root.cornerRadius
      color: root.selectedIndex === 1 ? root.hoverFill : "transparent"
      borderSpec: root.selectedIndex === 1 ? root.borderSpec : Border.none()

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        Text {
          width: parent.width - Style.space(8) - Style.space(16)
          y: Math.max(0, (parent.height - height) / 2)
          textFormat: Text.PlainText
          text: "Show finished items on the tile"
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
          opacity: root.showDone ? 1 : 0
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.selectedIndex = 1
        onClicked: root.toggleShowDone()
      }
    }
  }
}
