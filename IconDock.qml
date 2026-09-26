import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

Item {
  id: root

  property var items: []
  property var desktopApps: null
  property int catalogRevision: 0
  property int iconSize: Style.space(56)
  property int gap: Style.spacing.md
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color hoverFill: Color.menu.background
  property var idleBorderSpec: Border.none()
  property var selectedBorderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius
  property bool hintMode: false
  // Space-hint letters for dock icons (first = q, …).
  readonly property var hintLetters: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]

  signal activated(var item)

  readonly property var resolvedItems: {
    var _rev = root.catalogRevision
    return TileModel.resolveDock(root.items, root.desktopApps)
  }

  readonly property int contentWidth: {
    var n = root.resolvedItems.length
    if (n <= 0) return 0
    return n * root.iconSize + Math.max(0, n - 1) * root.gap
  }

  height: root.resolvedItems.length > 0 ? root.iconSize : 0
  implicitHeight: height
  implicitWidth: contentWidth
  visible: root.resolvedItems.length > 0

  Row {
    id: row
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.gap

    Repeater {
      model: root.resolvedItems.length

      BorderSurface {
        required property int index
        readonly property var item: root.resolvedItems[index] || { empty: true }
        readonly property bool empty: item.empty === true
        readonly property string iconName: String(item.iconName || "")
        readonly property string glyph: String(item.icon || "")
        readonly property string favicon: String(item.faviconUrl || item.faviconFallbackUrl || "")

        width: root.iconSize
        height: root.iconSize
        radius: Math.min(root.cornerRadius, Style.space(10))
        color: dockMouse.containsMouse ? root.hoverFill : root.background
        borderSpec: dockMouse.containsMouse ? root.selectedBorderSpec : root.idleBorderSpec
        opacity: empty ? 0.5 : 1

        Image {
          id: themedIcon
          anchors.centerIn: parent
          width: Math.round(root.iconSize * 0.62)
          height: width
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          asynchronous: true
          visible: status === Image.Ready
          source: {
            if (root.desktopApps && iconName)
              return root.desktopApps.iconSource(iconName)
            if (favicon) return favicon
            return ""
          }
        }

        Text {
          anchors.centerIn: parent
          visible: !themedIcon.visible
          textFormat: Text.PlainText
          text: glyph || "󰣆"
          color: dockMouse.containsMouse ? root.foreground : root.foreground
          opacity: dockMouse.containsMouse ? 1 : 0.85
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        MouseArea {
          id: dockMouse
          anchors.fill: parent
          enabled: !empty
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.activated(item)
        }

        Rectangle {
          visible: root.hintMode && index < root.hintLetters.length
          width: Math.round(Math.min(parent.width, parent.height) * 0.72)
          height: width
          radius: width / 2
          anchors.centerIn: parent
          color: root.hoverFill
          border.width: Math.max(1, Style.space(2))
          border.color: root.foreground
          z: 3

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.hintLetters[index] || ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Math.round(parent.width * 0.58)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }
  }
}
