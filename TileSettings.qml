import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

Item {
  id: root

  property var tiles: []
  property var appLibrary: null
  property int catalogRevision: 0
  property int columns: 4
  property int rows: 2
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color hoverFill: Color.menu.background
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding

  signal saveTiles(var tiles)
  signal closed()

  readonly property int slotCount: Math.max(0, root.columns * root.rows)
  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.appLibrary)
  }

  property int pickingIndex: -1
  property string filterText: ""
  property string urlText: ""
  property int selectedIndex: 0
  readonly property bool picking: root.pickingIndex >= 0

  ListModel { id: appModel }

  function handleEscape() {
    if (root.pickingIndex >= 0) {
      root.stopPicking()
      return true
    }
    root.closed()
    return true
  }

  function stopPicking() {
    root.pickingIndex = -1
    root.filterText = ""
    root.urlText = ""
    root.selectedIndex = 0
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function persist(next) {
    root.saveTiles(next)
  }

  function replaceSlot(index, tile) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = TileModel.storedTile(tile)
    root.persist(next)
    root.stopPicking()
  }

  function clearSlot(index) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = null
    root.persist(next)
    if (root.pickingIndex === index) root.stopPicking()
  }

  function rebuildApps() {
    var _rev = root.catalogRevision
    appModel.clear()
    if (!root.appLibrary) return
    var rows = root.appLibrary.sortedEntries(root.filterText)
    var limit = Math.min(rows.length, 80)
    for (var i = 0; i < limit; i++) {
      var entry = rows[i] && rows[i].entry
      if (!entry) continue
      appModel.append({
        appId: String(entry.id || ""),
        name: root.appLibrary.entryName(entry),
        detail: root.appLibrary.entrySubtext(entry),
        iconName: String(entry.icon || "")
      })
    }
    if (appModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= appModel.count) root.selectedIndex = appModel.count - 1
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuildApps()
  }

  function chooseIndex(index) {
    if (index < 0 || index >= appModel.count) return
    var row = appModel.get(index)
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    var entry = null
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].entry && String(rows[i].entry.id || "") === row.appId) {
        entry = rows[i].entry
        break
      }
    }
    var tile = TileModel.fromDesktopEntry(entry, root.appLibrary)
    if (!tile && row)
      tile = { type: "app", desktop: TileModel.normalizeDesktopId(row.appId), label: row.name, iconName: row.iconName }
    if (tile) root.replaceSlot(root.pickingIndex, tile)
  }

  function chooseUrl() {
    var tile = TileModel.fromUrl(root.urlText)
    if (tile) root.replaceSlot(root.pickingIndex, tile)
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.handleEscape()
      return true
    }
    if (!root.picking) return false
    if (urlField.activeFocus) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.chooseUrl()
        return true
      }
      return false
    }
    if (event.key === Qt.Key_Up) {
      if (appModel.count > 0)
        root.selectedIndex = (root.selectedIndex - 1 + appModel.count) % appModel.count
      return true
    }
    if (event.key === Qt.Key_Down) {
      if (appModel.count > 0)
        root.selectedIndex = (root.selectedIndex + 1) % appModel.count
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (appModel.count > 0) root.chooseIndex(root.selectedIndex)
      else root.chooseUrl()
      return true
    }
    if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
      return true
    }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
      root.setFilter(root.filterText + event.text)
      return true
    }
    return false
  }

  onVisibleChanged: {
    if (visible) {
      root.pickingIndex = -1
      root.filterText = ""
      root.urlText = ""
      root.selectedIndex = 0
      root.rebuildApps()
      Qt.callLater(function() { keyScope.forceActiveFocus() })
    }
  }

  onPickingChanged: {
    if (root.picking) {
      root.filterText = ""
      root.urlText = ""
      root.selectedIndex = 0
      root.rebuildApps()
      Qt.callLater(function() { keyScope.forceActiveFocus() })
    }
  }

  onCatalogRevisionChanged: if (visible && root.picking) root.rebuildApps()

  BorderSurface {
    anchors.fill: parent
    radius: root.cornerRadius
    color: Color.menu.background
    borderSpec: root.borderSpec
  }

  MouseArea { anchors.fill: parent; onClicked: {} }

  Item {
    id: keyScope
    anchors.fill: parent
    anchors.margins: root.contentMargin
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (root.handleKey(event)) event.accepted = true
    }

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.right: doneButton.left
      anchors.rightMargin: Style.spacing.md
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.picking ? ("Slot " + (root.pickingIndex + 1) + " · Application") : "Tiles"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Button {
      id: doneButton
      anchors.right: parent.right
      anchors.verticalCenter: titleText.verticalCenter
      text: root.picking ? "Back" : "Done"
      fontFamily: root.fontFamily
      foreground: root.foreground
      bordered: true
      onClicked: root.handleEscape()
    }

    ListView {
      id: slotList
      visible: !root.picking
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.slotCount

      delegate: BorderSurface {
        required property int index
        readonly property var tile: root.resolvedTiles[index] || { empty: true }
        readonly property bool empty: tile.empty === true

        width: ListView.view.width
        height: Style.space(50)
        radius: root.cornerRadius
        color: slotMouse.containsMouse ? root.hoverFill : "transparent"
        borderSpec: slotMouse.containsMouse ? root.borderSpec : Border.none()

        Text {
          id: slotIndexText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          textFormat: Text.PlainText
          text: String(index + 1)
          color: slotMouse.containsMouse ? root.selectedText : root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Image {
          id: slotIcon
          visible: !empty && (String(tile.faviconUrl || "").length > 0 || String(tile.iconName || "").length > 0)
          width: Style.font.iconLarge
          height: Style.font.iconLarge
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: {
            if (String(tile.faviconUrl || "").length > 0) return tile.faviconUrl
            if (String(tile.iconName || "").length > 0 && root.appLibrary) return root.appLibrary.iconSource(tile.iconName)
            return ""
          }
          asynchronous: true
          cache: true
          anchors.left: slotIndexText.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: slotGlyph
          visible: !slotIcon.visible
          anchors.left: slotIndexText.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          textFormat: Text.PlainText
          text: empty ? "·" : String(tile.icon || "󰣆")
          color: slotMouse.containsMouse ? root.selectedText : root.foreground
          opacity: empty ? 0.4 : 1
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          anchors.left: slotIcon.visible ? slotIcon.right : slotGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: clearButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: empty ? "Empty" : String(tile.label || "App")
          color: slotMouse.containsMouse ? root.selectedText : root.foreground
          opacity: empty ? 0.55 : 1
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        Button {
          id: clearButton
          visible: !empty
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "Clear"
          fontFamily: root.fontFamily
          foreground: root.foreground
          onClicked: root.clearSlot(index)
        }

        MouseArea {
          id: slotMouse
          anchors.fill: parent
          anchors.rightMargin: clearButton.visible ? clearButton.width + Style.space(8) : 0
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pickingIndex = index
        }
      }
    }

    Text {
      id: searchText
      visible: root.picking
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Search apps…"
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    Row {
      id: actionRow
      visible: root.picking
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: Style.spacing.sm

      Button {
        text: "Clear slot"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: root.clearSlot(root.pickingIndex)
      }
    }

    TextField {
      id: urlField
      visible: root.picking
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: actionRow.top
      anchors.bottomMargin: Style.spacing.sm
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      foreground: root.foreground
      placeholderText: "Or paste a URL…"
      text: root.urlText
      onTextChanged: root.urlText = text
      onAccepted: root.chooseUrl()
    }

    ListView {
      id: appList
      visible: root.picking
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: urlField.top
      anchors.bottomMargin: Style.spacing.sm
      clip: true
      model: appModel
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selectedIndex

      delegate: BorderSurface {
        required property int index
        required property string appId
        required property string name
        required property string detail
        required property string iconName

        width: ListView.view.width
        height: Style.space(44)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0) : Border.none()

        Image {
          width: Style.font.iconLarge
          height: Style.font.iconLarge
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: iconName && root.appLibrary ? root.appLibrary.iconSource(iconName) : ""
          asynchronous: true
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(36)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: name
          color: index === root.selectedIndex ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.chooseIndex(index)
        }
      }
    }
  }
}
