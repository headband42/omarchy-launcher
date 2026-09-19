import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property bool empty: true
  property string label: ""
  property string icon: ""
  property string iconName: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var idleBorderSpec: Border.none()
  property var selectedBorderSpec: Border.none()
  property var appLibrary: null

  signal activated()

  readonly property bool hot: mouseArea.containsMouse
  readonly property bool hasAppIcon: !root.empty && root.iconName.length > 0
  readonly property bool hasGlyph: !root.empty && root.icon.length > 0

  radius: Style.cornerRadius
  color: root.empty ? "transparent" : (root.hot ? root.selectedBackground : Style.normalFillFor(root.foreground, Color.accent, Color.urgent))
  borderSpec: root.empty ? Border.none() : (root.hot ? root.selectedBorderSpec : root.idleBorderSpec)
  opacity: root.empty ? 0.28 : 1

  Text {
    id: glyph
    visible: root.hasGlyph && !root.hasAppIcon
    textFormat: Text.PlainText
    text: root.icon
    color: root.hot ? root.selectedText : root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.32)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.label.length > 0 ? -Style.space(10) : 0
  }

  Image {
    id: appIcon
    visible: root.hasAppIcon
    width: Math.round(Math.min(root.width, root.height) * 0.38)
    height: width
    fillMode: Image.PreserveAspectFit
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: root.hasAppIcon && root.appLibrary ? root.appLibrary.iconSource(root.iconName) : ""
    asynchronous: true
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.label.length > 0 ? -Style.space(10) : 0
  }

  Text {
    visible: !root.empty && root.label.length > 0
    textFormat: Text.PlainText
    text: root.label
    color: root.hot ? root.selectedText : root.foreground
    opacity: 0.9
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.weight: Font.Medium
    elide: Text.ElideRight
    width: parent.width - Style.space(16)
    horizontalAlignment: Text.AlignHCenter
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(10)
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    enabled: !root.empty
    hoverEnabled: enabled
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }
}
