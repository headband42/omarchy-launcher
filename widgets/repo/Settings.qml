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

  implicitWidth: Style.space(360)
  implicitHeight: Style.space(130)

  function commit() {
    var value = String(pathField.text || "").trim()
    root.settings = value ? { path: value } : {}
    root.forceActiveFocus()
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    return false
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Repository to watch"
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
      placeholderText: "Empty watches your home directory"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onEditingFinished: root.commit()
      onAccepted: root.commit()
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Clicking the tile opens lazygit in this directory."
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
