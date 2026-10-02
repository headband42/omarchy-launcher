import QtQuick
import qs.Commons
import qs.Ui

// A settings-panel row: a title and a note, and a state pill on the right.
//
//   OptionRow {
//     width: parent.width
//     selected: root.selectedIndex === 2
//     title: "Reset style"
//     note: "How long until a block frees up"
//     tag: "countdown"
//     lit: true                      // the pill takes the accent
//     hoverFill: root.hoverFill
//     selectedBorder: root.borderSpec
//     cornerRadius: root.cornerRadius
//     fontFamily: root.fontFamily
//     foreground: root.foreground
//     onHovered: root.selectedIndex = 2
//     onPicked: root.toggleStyle()
//   }
BorderSurface {
  id: option

  property bool selected: false
  property string title: ""
  property string note: ""
  property string tag: ""
  property bool lit: false
  property color hoverFill: Color.menu.background
  // The border a selected row draws.
  property var selectedBorder: Border.none()
  property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  signal picked()
  signal hovered()

  height: Style.space(48)
  radius: option.cornerRadius
  color: option.selected ? option.hoverFill : "transparent"
  borderSpec: option.selected ? option.selectedBorder : Border.none()

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: pill.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: option.title
      color: option.foreground
      font.family: option.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: text.length > 0
      width: parent.width
      textFormat: Text.PlainText
      text: option.note
      color: option.foreground
      opacity: 0.55
      font.family: option.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Rectangle {
    id: pill
    visible: option.tag.length > 0
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    radius: height / 2
    color: option.lit ? Util.alpha(Color.accent, 0.24) : Util.alpha(option.foreground, 0.06)
    implicitWidth: tagText.implicitWidth + Style.space(14)
    implicitHeight: tagText.implicitHeight + Style.space(4)

    Text {
      id: tagText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: option.tag
      color: option.foreground
      opacity: option.lit ? 1 : 0.55
      font.family: option.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: option.hovered()
    onClicked: option.picked()
  }
}
