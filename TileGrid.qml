import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property int columns: 4
  property int rows: 2
  property int tileSize: Style.space(88)
  property int gap: Style.spacing.md
  property var tiles: []
  property var appLibrary: null
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var idleBorderSpec: Border.none()
  property var selectedBorderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius

  signal activated(var tile)

  readonly property int slotCount: Math.max(0, root.columns * root.rows)

  width: root.columns > 0 ? root.columns * root.tileSize + Math.max(0, root.columns - 1) * root.gap : 0
  height: root.rows > 0 ? root.rows * root.tileSize + Math.max(0, root.rows - 1) * root.gap : 0

  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  readonly property var resolvedTiles: {
    var byId = ({})
    if (root.appLibrary) {
      var rows = root.appLibrary.sortedEntries("")
      for (var i = 0; i < rows.length; i++) {
        var entry = rows[i] && rows[i].entry
        if (entry && entry.id) byId[String(entry.id)] = entry
      }
    }

    var source = Array.isArray(root.tiles) ? root.tiles : []
    var out = []
    for (var j = 0; j < root.slotCount; j++) {
      var tile = source[j]
      if (!tile || typeof tile !== "object") {
        out.push({ empty: true, label: "", icon: "", iconName: "", desktop: "", command: "", url: "" })
        continue
      }

      var desktop = String(tile.desktop || "").replace(/\.desktop$/i, "")
      var entry = desktop ? byId[desktop] : null
      var label = String(tile.label || "")
      if (!label && entry && root.appLibrary) label = root.appLibrary.entryName(entry)
      if (!label) label = desktop || String(tile.url || "")

      out.push({
        empty: false,
        label: label,
        icon: String(tile.icon || ""),
        iconName: String(tile.iconName || (entry && entry.icon) || ""),
        desktop: desktop,
        command: String(tile.command || ""),
        url: String(tile.url || "")
      })
    }
    return out
  }

  Repeater {
    model: root.slotCount

    Tile {
      required property int index

      readonly property var tile: root.resolvedTiles[index] || { empty: true }

      x: (index % root.columns) * (root.tileSize + root.gap)
      y: Math.floor(index / root.columns) * (root.tileSize + root.gap)
      width: root.tileSize
      height: root.tileSize
      empty: tile.empty === true
      label: String(tile.label || "")
      icon: String(tile.icon || "")
      iconName: String(tile.iconName || "")
      fontFamily: root.fontFamily
      foreground: root.foreground
      selectedBackground: root.selectedBackground
      selectedText: root.selectedText
      idleBorderSpec: root.idleBorderSpec
      selectedBorderSpec: root.selectedBorderSpec
      appLibrary: root.appLibrary
      radius: root.cornerRadius
      onActivated: root.activated(tile)
    }
  }
}
