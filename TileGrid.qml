import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

Item {
  id: root

  property int columns: 4
  property int rows: 2
  property int tileSize: Style.space(88)
  property int gap: Style.spacing.md
  property var tiles: []
  property var appLibrary: null
  property int catalogRevision: 0
  property var widgetCatalog: []
  property var desktopApps: null
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color hoverFill: Color.menu.background
  property color selectedText: Color.menu.selectedText
  property var idleBorderSpec: Border.none()
  property var selectedBorderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius
  property bool hintMode: false

  signal activated(var tile)
  signal openFolder(string path)
  signal openTerminal(string path)
  signal openVolume(string path, string device)

  readonly property int slotCount: Math.max(0, root.columns * root.rows)

  width: root.columns > 0 ? root.columns * root.tileSize + Math.max(0, root.columns - 1) * root.gap : 0
  height: root.rows > 0 ? root.rows * root.tileSize + Math.max(0, root.rows - 1) * root.gap : 0

  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.desktopApps, root.widgetCatalog)
  }

  Repeater {
    model: root.slotCount

    Item {
      required property int index

      readonly property var tile: root.resolvedTiles[index] || { empty: true }

      x: (index % root.columns) * (root.tileSize + root.gap)
      y: Math.floor(index / root.columns) * (root.tileSize + root.gap)
      width: root.tileSize
      height: root.tileSize

      BorderSurface {
        anchors.fill: parent
        radius: root.cornerRadius
        color: tileMouse.containsMouse ? root.hoverFill : root.background
        borderSpec: tileMouse.containsMouse ? root.selectedBorderSpec : root.idleBorderSpec
        opacity: tile.empty === true ? 0.7 : 1

        MouseArea {
          id: tileMouse
          z: 0
          anchors.fill: parent
          enabled: tile.empty !== true
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.activated(tile)
        }

        Loader {
          id: widgetLoader
          z: 1
          anchors.fill: parent
          active: String(tile.widgetQml || "").length > 0 || String(tile.widget || "").length > 0
          source: {
            if (String(tile.widgetQml || "").length > 0) {
              var path = String(tile.widgetQml)
              return path.indexOf("file://") === 0 ? path : ("file://" + path)
            }
            if (String(tile.widget || "").length > 0)
              return Qt.resolvedUrl("widgets/" + tile.widget + "/Widget.qml")
            return ""
          }
          visible: status === Loader.Ready
          onLoaded: {
            if (!item) return
            if ("fontFamily" in item) item.fontFamily = root.fontFamily
            if ("foreground" in item) item.foreground = root.foreground
            if ("host" in item) {
              item.host = {
                launchDefault: function() { root.activated(tile) },
                openFolder: function(path) { root.openFolder(path) },
                openTerminal: function(path) { root.openTerminal(path) },
                openVolume: function(path, device) { root.openVolume(path, device) }
              }
            }
          }
        }

        Binding {
          target: widgetLoader.item
          property: "tile"
          value: tile
          when: widgetLoader.status === Loader.Ready && widgetLoader.item
        }

        Tile {
          z: 1
          anchors.fill: parent
          visible: widgetLoader.status !== Loader.Ready
          empty: tile.empty === true
          label: String(tile.label || "")
          icon: String(tile.icon || "")
          iconName: String(tile.iconName || "")
          faviconUrl: String(tile.faviconUrl || "")
          faviconFallbackUrl: String(tile.faviconFallbackUrl || "")
          fontFamily: root.fontFamily
          foreground: root.foreground
          background: "transparent"
          hoverFill: "transparent"
          selectedText: root.selectedText
          idleBorderSpec: Border.none()
          selectedBorderSpec: Border.none()
          appLibrary: root.appLibrary
          desktopApps: root.desktopApps
          radius: root.cornerRadius
          onActivated: root.activated(tile)
        }
      }

      Rectangle {
        visible: root.hintMode
        width: Math.round(Math.min(parent.width, parent.height) * 0.46)
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
          text: String(index + 1)
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
