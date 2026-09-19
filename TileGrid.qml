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
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var idleBorderSpec: Border.none()
  property var selectedBorderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius
  property bool editMode: false
  property int editingIndex: -1

  signal activated(var tile)
  signal saveTiles(var tiles)

  readonly property int slotCount: Math.max(0, root.columns * root.rows)
  readonly property bool picking: root.editMode && root.editingIndex >= 0

  width: root.columns > 0 ? root.columns * root.tileSize + Math.max(0, root.columns - 1) * root.gap : 0
  height: root.rows > 0 ? root.rows * root.tileSize + Math.max(0, root.rows - 1) * root.gap : 0

  function handleEscape() {
    if (root.editingIndex >= 0) {
      root.editingIndex = -1
      return true
    }
    if (root.editMode) {
      root.editMode = false
      return true
    }
    return false
  }

  function replaceSlot(index, tile) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = TileModel.storedTile(tile)
    root.saveTiles(next)
    root.editingIndex = -1
  }

  function clearSlot(index) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = null
    root.saveTiles(next)
    root.editingIndex = -1
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.appLibrary)
  }

  Repeater {
    model: root.picking ? 0 : root.slotCount

    Tile {
      required property int index

      readonly property var tile: root.resolvedTiles[index] || { empty: true }

      x: (index % root.columns) * (root.tileSize + root.gap)
      y: Math.floor(index / root.columns) * (root.tileSize + root.gap)
      width: root.tileSize
      height: root.tileSize
      empty: tile.empty === true
      editMode: root.editMode
      label: String(tile.label || "")
      icon: String(tile.icon || "")
      iconName: String(tile.iconName || "")
      fontFamily: root.fontFamily
      foreground: root.foreground
      background: root.background
      selectedBackground: root.selectedBackground
      selectedText: root.selectedText
      idleBorderSpec: root.idleBorderSpec
      selectedBorderSpec: root.selectedBorderSpec
      appLibrary: root.appLibrary
      radius: root.cornerRadius
      onActivated: {
        if (root.editMode) root.editingIndex = index
        else root.activated(tile)
      }
    }
  }

  TileSettings {
    id: picker
    visible: root.picking
    anchors.fill: parent
    appLibrary: root.appLibrary
    catalogRevision: root.catalogRevision
    slotIndex: Math.max(0, root.editingIndex)
    fontFamily: root.fontFamily
    foreground: root.foreground
    selectedBackground: root.selectedBackground
    selectedText: root.selectedText
    onChosen: function(tile) { root.replaceSlot(root.editingIndex, tile) }
    onCleared: root.clearSlot(root.editingIndex)
    onCancelled: root.editingIndex = -1
  }

  BorderSurface {
    id: gear
    z: 4
    width: Style.space(32)
    height: Style.space(32)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(6)
    anchors.topMargin: Style.space(6)
    visible: !root.picking
    radius: Style.cornerRadius
    color: gearMouse.containsMouse ? root.selectedBackground : root.background
    borderSpec: root.idleBorderSpec

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.editMode ? "󰄬" : ""
      color: gearMouse.containsMouse ? root.selectedText : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: gearMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.editingIndex = -1
        root.editMode = !root.editMode
      }
    }
  }
}
