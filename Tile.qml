import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property bool empty: true
  property bool editMode: false
  property string label: ""
  property string icon: ""
  property string iconName: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color background: Color.menu.background
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
  color: root.hot ? root.selectedBackground : root.background
  borderSpec: root.hot ? root.selectedBorderSpec : root.idleBorderSpec
  opacity: root.empty && !root.editMode ? 0.55 : 1

  Text {
    id: glyph
    visible: (root.hasGlyph && !root.hasAppIcon) || (root.empty && root.editMode && !root.hasAppIcon && !root.hasGlyph)
    textFormat: Text.PlainText
    text: root.empty ? "" : root.icon
    color: root.hot ? root.selectedText : root.foreground
    opacity: root.empty ? 0.45 : 1
    font.family: root.fontFamily
    font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.32)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: (root.empty ? "Empty" : root.label).length > 0 ? -Style.space(10) : 0
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
    visible: root.editMode || (!root.empty && root.label.length > 0)
    textFormat: Text.PlainText
    text: root.empty ? "Empty" : root.label
    color: root.hot ? root.selectedText : root.foreground
    opacity: root.empty ? 0.55 : 0.9
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
    enabled: root.editMode || !root.empty
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }
}
