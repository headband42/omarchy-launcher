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
  property bool compact: false

  Column {
    anchors.fill: parent
    spacing: Math.max(2, Math.round(root.height * 0.08))

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        width: Math.min(Style.space(42), parent.width * 0.28)
        textFormat: Text.PlainText
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.compact ? Style.font.caption : Style.font.body
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Text {
        width: parent.width - parent.children[0].width - parent.spacing
        textFormat: Text.PlainText
        text: root.detail
        color: root.foreground
        opacity: 0.62
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(root.compact ? 3 : 5, Math.round(root.height * 0.18))
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Rectangle {
        width: Math.max(height, Math.min(1, Math.max(0, root.value)) * parent.width)
        height: parent.height
        radius: parent.radius
        color: root.fill
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      }
    }
  }
}
