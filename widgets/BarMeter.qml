import QtQuick
import qs.Commons

Item {
  id: root
  property string label: ""
  property string detail: ""
  property real value: 0
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color fill: Color.accent

  height: Math.max(Style.space(16), Math.round(parent ? parent.height / 4.6 : Style.space(16)))

  Text {
    id: nameText
    anchors.left: parent.left
    anchors.top: parent.top
    width: Style.space(36)
    textFormat: Text.PlainText
    text: root.label
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, Style.font.caption - 1)
    elide: Text.ElideRight
  }

  Text {
    anchors.left: nameText.right
    anchors.leftMargin: Style.space(4)
    anchors.right: parent.right
    anchors.verticalCenter: nameText.verticalCenter
    textFormat: Text.PlainText
    text: root.detail
    color: root.foreground
    opacity: 0.7
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, Style.font.caption - 1)
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignRight
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(3, Style.space(4))
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

    Rectangle {
      width: Math.max(0, Math.min(1, root.value)) * parent.width
      height: parent.height
      radius: parent.radius
      color: root.fill
    }
  }
}
