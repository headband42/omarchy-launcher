import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property bool empty: true
  property string label: ""
  property string icon: ""
  property string iconName: ""
  property string faviconUrl: ""
  property string faviconFallbackUrl: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color hoverFill: Color.menu.background
  property color selectedText: Color.menu.selectedText
  property var idleBorderSpec: Border.none()
  property var selectedBorderSpec: Border.none()
  property var appLibrary: null
  property var desktopApps: null

  signal activated()

  property int iconAttempt: 0

  readonly property bool hot: mouseArea.containsMouse
  readonly property string themedIconSource: {
    if (root.empty || root.iconName.length === 0) return ""
    if (root.desktopApps && typeof root.desktopApps.iconSource === "function")
      return String(root.desktopApps.iconSource(root.iconName) || "")
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function")
      return String(root.appLibrary.iconSource(root.iconName) || "")
    return ""
  }
  readonly property string imageSource: {
    if (root.empty) return ""
    if (root.themedIconSource.length > 0) return root.themedIconSource
    if (root.faviconUrl.length > 0 && root.iconAttempt === 0) return root.faviconUrl
    if (root.faviconFallbackUrl.length > 0 && root.iconAttempt <= 1) return root.faviconFallbackUrl
    return ""
  }
  readonly property bool hasImage: root.imageSource.length > 0
  readonly property bool hasGlyph: !root.empty && root.icon.length > 0 && !root.hasImage

  radius: Style.cornerRadius
  color: root.hot ? root.hoverFill : root.background
  borderSpec: root.hot ? root.selectedBorderSpec : root.idleBorderSpec
  opacity: root.empty ? 0.7 : 1

  onFaviconUrlChanged: root.iconAttempt = 0
  onFaviconFallbackUrlChanged: root.iconAttempt = 0
  onIconNameChanged: root.iconAttempt = 0

  Text {
    id: glyph
    visible: root.hasGlyph
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
    visible: root.hasImage
    width: Math.round(Math.min(root.width, root.height) * 0.38)
    height: width
    fillMode: Image.PreserveAspectFit
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: root.imageSource
    asynchronous: true
    cache: true
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.label.length > 0 ? -Style.space(10) : 0
    onStatusChanged: {
      if (status === Image.Error && root.iconAttempt < 2) root.iconAttempt += 1
    }
  }

  Text {
    visible: !root.empty && root.label.length > 0
    textFormat: Text.PlainText
    text: root.label
    color: root.hot ? root.selectedText : root.foreground
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
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }
}
