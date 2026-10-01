import QtQuick
import qs.Commons

// The status dot and spaced caption at the top of a widget, with an optional
// value on the right.
//
//   WidgetHeader {
//     title: "UPDATES"
//     trailing: root.sample.channel
//     dotColor: root.count > 0 ? Color.accent : root.foreground
//     dotOpacity: root.count > 0 ? 1 : 0.35
//     pulse: root.count > 0
//     fontFamily: root.fontFamily
//     foreground: root.foreground
//   }
Item {
  id: header

  property string title: ""
  property string trailing: ""
  property color dotColor: Color.accent
  property real dotOpacity: 1
  property bool pulse: false
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  width: parent ? parent.width : 0
  height: Style.font.caption + 4

  Rectangle {
    id: dot
    width: 6
    height: 6
    radius: 3
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    color: header.dotColor
    opacity: header.dotOpacity

    SequentialAnimation on opacity {
      running: header.pulse
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.4; duration: 900; easing.type: Easing.InOutQuad }
      NumberAnimation { from: 0.4; to: 1; duration: 900; easing.type: Easing.InOutQuad }
    }
  }

  Text {
    id: caption
    anchors.left: dot.right
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: header.title
    color: header.foreground
    opacity: 0.6
    font.family: header.fontFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.Medium
    font.letterSpacing: 1
  }

  Text {
    visible: header.trailing.length > 0
    anchors.left: caption.right
    anchors.leftMargin: Style.space(6)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: header.trailing
    color: header.foreground
    opacity: 0.6
    font.family: header.fontFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.DemiBold
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
  }
}
