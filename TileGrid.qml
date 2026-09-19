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

  readonly property int slotCount: Math.max(0, root.columns * root.rows)

  width: root.columns > 0 ? root.columns * root.tileSize + Math.max(0, root.columns - 1) * root.gap : 0
  height: root.rows > 0 ? root.rows * root.tileSize + Math.max(0, root.rows - 1) * root.gap : 0

  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.appLibrary)
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

      Tile {
        anchors.fill: parent
        empty: tile.empty === true
        label: String(tile.label || "")
        icon: String(tile.icon || "")
        iconName: String(tile.iconName || "")
        faviconUrl: String(tile.faviconUrl || "")
        faviconFallbackUrl: String(tile.faviconFallbackUrl || "")
        fontFamily: root.fontFamily
        foreground: root.foreground
        background: root.background
        hoverFill: root.hoverFill
        selectedText: root.selectedText
        idleBorderSpec: root.idleBorderSpec
        selectedBorderSpec: root.selectedBorderSpec
        appLibrary: root.appLibrary
        radius: root.cornerRadius
        onActivated: root.activated(tile)
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
