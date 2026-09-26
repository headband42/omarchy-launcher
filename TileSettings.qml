import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

// Larger, keyboard-first launcher settings. Arrows / j-k move, Enter
// activates, Esc backs out. Every row shows a focus ring when selected —
// nothing useful is mouse-only.
Item {
  id: root

  property var tiles: []
  property var appLibrary: null
  property var widgetCatalog: []
  property var desktopApps: null
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
  property int hostHeight: 0

  property var widgetSettings: null
  property var dock: []

  signal saveTiles(var tiles, var widgetSettings)
  signal saveDock(var dock)
  signal closed()

  // Home views use a roomier panel than the launcher card.
  readonly property int preferredWidth: Style.space(640)
  readonly property int preferredHeight: Style.space(560)

  readonly property int slotCount: Math.max(0, root.columns * root.rows)
  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.desktopApps, root.widgetCatalog, root.widgetSettings)
  }
  readonly property var catalog: {
    var list = Array.isArray(root.widgetCatalog) ? root.widgetCatalog.slice() : []
    var hasNone = false
    for (var i = 0; i < list.length; i++) {
      if (!String(list[i].id || "")) { hasNone = true; break }
    }
    if (!hasNone) {
      list.unshift({
        id: "",
        name: "Icon & link",
        description: "No widget. The tile is just the icon for the app or site it opens.",
        icon: "󰖟"
      })
    }
    return list
  }

  // slots | edit | widgets | opens | webapp | panel | dock | dock-add
  property string view: "slots"
  property int activeIndex: 0
  property string panelReturn: "edit"
  property string filterText: ""
  property int selectedIndex: 0
  property var appRows: []
  property int appCount: 0
  property string webName: ""
  property string webUrl: ""

  readonly property var activeTile: root.resolvedTiles[root.activeIndex] || { empty: true }
  readonly property var dockList: Array.isArray(root.dock) ? root.dock : []
  readonly property int dockCount: root.dockList.length
  readonly property var resolvedDock: {
    var _rev = root.catalogRevision
    return TileModel.resolveDock(root.dockList, root.desktopApps)
  }

  // Home list: one row per slot, then the icon-dock entry.
  readonly property int homeCount: root.slotCount + 1
  readonly property int editCount: 3
  // Dock list: "+ Add app" then each icon.
  readonly property int dockNavCount: root.dockCount + 1

  readonly property bool fitPanel: root.view === "panel"
      && settingsLoader.status === Loader.Ready
      && settingsLoader.item
      && settingsLoader.item.implicitWidth > 0
      && settingsLoader.item.implicitHeight > 0
  readonly property int fittedWidth: {
    if (!root.fitPanel) return 0
    var pad = root.contentMargin * 2
    var content = settingsLoader.item.implicitWidth + pad
    var title = titleText.implicitWidth + doneButton.implicitWidth + Style.spacing.md + pad
    return Math.ceil(Math.max(content, title))
  }
  readonly property int fittedHeight: {
    if (!root.fitPanel) return 0
    var pad = root.contentMargin * 2
    return Math.ceil(pad + titleText.implicitHeight + Style.spacing.md + settingsLoader.item.implicitHeight)
  }

  function handleEscape() {
    if (root.view === "panel") {
      if (settingsLoader.item && settingsLoader.item.handleEscape && settingsLoader.item.handleEscape())
        return true
      root.view = root.panelReturn || "edit"
      root.selectedIndex = 0
      return true
    }
    if (root.view === "dock-add") { root.view = "dock"; root.selectedIndex = 0; return true }
    if (root.view === "dock") { root.view = "slots"; root.selectedIndex = root.slotCount; return true }
    if (root.view === "webapp") {
      root.view = root.panelReturn === "dock" ? "dock-add" : "opens"
      root.panelReturn = "edit"
      root.selectedIndex = 0
      return true
    }
    if (root.view === "widgets" || root.view === "opens") {
      var backTo = root.view === "widgets" ? 0 : 1
      root.view = "edit"
      root.selectedIndex = backTo
      return true
    }
    if (root.view === "edit") { root.view = "slots"; root.selectedIndex = root.activeIndex; return true }
    root.closed()
    return true
  }

  function hasSettings(entry) {
    return !!(entry && String(entry.settingsQml || "").length > 0)
  }

  function openPanel(index, returnView) {
    root.activeIndex = index
    root.panelReturn = returnView || "edit"
    if (!root.hasSettings(root.resolvedTiles[index])) return
    root.view = "panel"
  }

  function configureWidget(widget) {
    var current = root.slotAt(root.activeIndex)
    var nextId = String((widget && widget.id) || "")
    if (nextId !== TileModel.widgetId(current))
      root.writeSlot(root.activeIndex, TileModel.applyWidget(current, widget, root.widgetSettings))
    if (!root.hasSettings(widget)) {
      root.view = "edit"
      root.selectedIndex = 0
      return
    }
    root.panelReturn = "edit"
    root.view = "panel"
  }

  property bool applyingSettings: false
  property bool panelHasSettings: false

  function publishedSettings() {
    var tile = root.activeTile
    var settings = tile && tile.settings
    if (!settings || typeof settings !== "object" || Array.isArray(settings)) return ({})
    if (Object.keys(settings).length === 0) return ({})
    return settings
  }

  function pushPanelSettings() {
    var item = settingsLoader.item
    if (!item || !root.panelHasSettings) return
    root.applyingSettings = true
    item.settings = root.publishedSettings()
    root.applyingSettings = false
  }

  function writeSettings(settings) {
    var id = TileModel.widgetId(root.slotAt(root.activeIndex))
    var saved = TileModel.saveWidgetSettings(root.tiles, root.slotCount, root.widgetSettings, id, settings)
    if (!saved.changed) return
    root.saveTiles(saved.tiles, saved.widgetSettings)
  }

  readonly property string activeSettingsSource: {
    var tile = root.resolvedTiles[root.activeIndex] || null
    var path = tile ? String(tile.settingsQml || "") : ""
    if (!path) return ""
    return path.indexOf("file://") === 0 ? path : ("file://" + path)
  }

  function titleForView() {
    if (root.view === "widgets") return "Widget · slot " + (root.activeIndex + 1)
    if (root.view === "opens") return "Opens · " + root.appCount + " apps"
    if (root.view === "dock") return "Icon dock · " + root.dockCount + " icons"
    if (root.view === "dock-add") return "Add dock icon · " + root.appCount + " apps"
    if (root.view === "webapp") return "New web app"
    if (root.view === "edit") return "Slot " + (root.activeIndex + 1)
    if (root.view === "panel") {
      var custom = settingsLoader.item ? String(settingsLoader.item.panelTitle || "") : ""
      if (custom) return custom
      return String((root.activeTile && root.activeTile.widgetName) || "Widget")
    }
    return "Launcher settings"
  }

  function persist(next) { root.saveTiles(next, root.widgetSettings) }

  function persistDock(next) {
    root.saveDock(TileModel.storedDock(next))
  }

  function openDock() {
    root.view = "dock"
    root.filterText = ""
    root.selectedIndex = 0
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function addDockItem(launch) {
    if (!launch) return
    var item = TileModel.storedDockItem(launch)
    if (!item) return
    var next = TileModel.storedDock(root.dockList)
    next.push(item)
    root.persistDock(next)
    root.view = "dock"
    root.filterText = ""
    root.selectedIndex = next.length
  }

  function removeDockAt(index) {
    var next = TileModel.storedDock(root.dockList)
    if (index < 0 || index >= next.length) return
    next.splice(index, 1)
    root.persistDock(next)
    root.selectedIndex = Math.min(root.selectedIndex, next.length)
  }

  function moveDock(index, delta) {
    var next = TileModel.storedDock(root.dockList)
    var dest = index + delta
    if (index < 0 || index >= next.length || dest < 0 || dest >= next.length) return
    var tmp = next[index]
    next[index] = next[dest]
    next[dest] = tmp
    root.persistDock(next)
    root.selectedIndex = dest + 1
  }

  function dockLabel(item) {
    if (!item || item.empty) return "Empty"
    return item.label || item.url || item.desktop || item.command || "App"
  }

  function slotAt(index) {
    var source = Array.isArray(root.tiles) ? root.tiles : []
    return source[index] && typeof source[index] === "object" ? source[index] : null
  }

  function writeSlot(index, tile) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = tile
    root.persist(next)
  }

  function openSlot(index) {
    root.activeIndex = index
    root.view = "edit"
    root.selectedIndex = 0
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function chooseWidget(widget) {
    root.writeSlot(root.activeIndex, TileModel.applyWidget(root.slotAt(root.activeIndex), widget, root.widgetSettings))
    root.view = "edit"
    root.selectedIndex = 0
  }

  function chooseLaunch(launch) {
    if (root.view === "dock-add") {
      root.addDockItem(launch)
      return
    }
    root.writeSlot(root.activeIndex, TileModel.applyLaunch(root.slotAt(root.activeIndex), launch))
    root.view = "edit"
    root.selectedIndex = 1
  }

  function clearSlot() {
    root.writeSlot(root.activeIndex, null)
    root.view = "slots"
    root.selectedIndex = root.activeIndex
  }

  function rebuildApps() {
    var _rev = root.catalogRevision
    var rows = root.desktopApps ? root.desktopApps.list(root.filterText) : []
    root.appRows = rows
    root.appCount = rows.length
    if (root.selectedIndex >= rows.length + 1) root.selectedIndex = Math.max(0, rows.length)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuildApps()
  }

  function createWebApp() {
    var launch = TileModel.fromUrl(root.webUrl, root.webName)
    if (!launch) return
    if (launch.label && launch.url)
      Util.execDetached("omarchy-webapp-install " + Util.shellQuote(launch.label) + " " + Util.shellQuote(launch.url) + " ''")
    root.chooseLaunch(launch)
    root.webName = ""
    root.webUrl = ""
  }

  function opensLabel(tile) {
    if (!tile || tile.empty) return "Not set"
    return tile.label || tile.url || tile.desktop || tile.command || "Not set"
  }

  function moveSelection(delta, count) {
    if (count <= 0) return
    root.selectedIndex = (root.selectedIndex + delta + count * 10) % count
  }

  function isNavUp(event) {
    return event.key === Qt.Key_Up || event.key === Qt.Key_K
      || (event.text === "k" && event.modifiers === Qt.NoModifier)
  }
  function isNavDown(event) {
    return event.key === Qt.Key_Down || event.key === Qt.Key_J
      || (event.text === "j" && event.modifiers === Qt.NoModifier)
  }
  function isActivate(event) {
    return event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right
  }
  function isBack(event) {
    return event.key === Qt.Key_Escape || event.key === Qt.Key_Left || event.key === Qt.Key_Backspace
  }

  function activateHome() {
    if (root.selectedIndex >= 0 && root.selectedIndex < root.slotCount) {
      root.openSlot(root.selectedIndex)
      return
    }
    if (root.selectedIndex === root.slotCount) root.openDock()
  }

  function activateEdit() {
    if (root.selectedIndex === 0) {
      root.view = "widgets"
      root.selectedIndex = 0
      return
    }
    if (root.selectedIndex === 1) {
      root.view = "opens"
      root.filterText = ""
      root.selectedIndex = 0
      root.rebuildApps()
      return
    }
    if (root.selectedIndex === 2) root.clearSlot()
  }

  function activateDock() {
    if (root.selectedIndex === 0) {
      root.filterText = ""
      root.selectedIndex = 0
      root.rebuildApps()
      root.view = "dock-add"
      return
    }
    // Focused dock icon: Delete removes; nothing else on Enter.
  }

  function handleKey(event) {
    if (root.view === "panel") {
      if (root.isBack(event)) return root.handleEscape()
      if (settingsLoader.item && settingsLoader.item.handleKey)
        return !!settingsLoader.item.handleKey(event)
      return false
    }
    if (root.isBack(event) && !(nameField.activeFocus || urlField.activeFocus)
        && !(root.view === "opens" || root.view === "dock-add")
        && event.key !== Qt.Key_Backspace) {
      root.handleEscape()
      return true
    }
    if (event.key === Qt.Key_Escape) { root.handleEscape(); return true }

    if (nameField.activeFocus || urlField.activeFocus) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.view === "webapp") root.createWebApp()
        return true
      }
      return false
    }

    if (root.view === "slots") {
      if (root.isNavUp(event)) { root.moveSelection(-1, root.homeCount); return true }
      if (root.isNavDown(event)) { root.moveSelection(1, root.homeCount); return true }
      if (root.isActivate(event)) { root.activateHome(); return true }
      return false
    }

    if (root.view === "edit") {
      if (root.isNavUp(event)) { root.moveSelection(-1, root.editCount); return true }
      if (root.isNavDown(event)) { root.moveSelection(1, root.editCount); return true }
      if (root.isActivate(event)) { root.activateEdit(); return true }
      // g opens widget settings gear when available
      if ((event.text === "g" || event.key === Qt.Key_G) && root.hasSettings(root.activeTile)) {
        root.openPanel(root.activeIndex, "edit")
        return true
      }
      return false
    }

    if (root.view === "dock") {
      if (root.isNavUp(event)) { root.moveSelection(-1, root.dockNavCount); return true }
      if (root.isNavDown(event)) { root.moveSelection(1, root.dockNavCount); return true }
      if (root.isActivate(event)) { root.activateDock(); return true }
      if (root.selectedIndex > 0) {
        var di = root.selectedIndex - 1
        if (event.key === Qt.Key_Delete || event.text === "x" || event.key === Qt.Key_X) {
          root.removeDockAt(di)
          return true
        }
        if (event.key === Qt.Key_Less || event.text === "<" || event.key === Qt.Key_H
            || (event.text === "h" && event.modifiers === Qt.NoModifier)) {
          root.moveDock(di, -1)
          return true
        }
        if (event.key === Qt.Key_Greater || event.text === ">" || event.key === Qt.Key_L
            || (event.text === "l" && event.modifiers === Qt.NoModifier)) {
          root.moveDock(di, 1)
          return true
        }
      }
      return false
    }

    if (root.view === "opens" || root.view === "dock-add") {
      var count = root.appCount + 1
      // Arrows navigate; printable text (including j/k) filters.
      if (event.key === Qt.Key_Up) { root.moveSelection(-1, count); return true }
      if (event.key === Qt.Key_Down) { root.moveSelection(1, count); return true }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
        if (root.selectedIndex === 0) {
          root.panelReturn = root.view === "dock-add" ? "dock" : "edit"
          root.view = "webapp"
          Qt.callLater(function() { nameField.forceActiveFocus() })
        } else {
          root.chooseLaunch(TileModel.fromAppRow(root.appRows[root.selectedIndex - 1]))
        }
        return true
      }
      if (Util.editsFilter(event, root.filterText)) { root.setFilter(Util.editedFilter(event, root.filterText)); return true }
      if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
          && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
        root.setFilter(root.filterText + event.text)
        return true
      }
      return false
    }

    if (root.view === "widgets") {
      var wcount = root.catalog.length
      if (root.isNavUp(event)) { root.moveSelection(-1, wcount); return true }
      if (root.isNavDown(event)) { root.moveSelection(1, wcount); return true }
      if (root.isActivate(event)) {
        root.chooseWidget(root.catalog[root.selectedIndex])
        return true
      }
      if ((event.text === "g" || event.key === Qt.Key_G) && root.hasSettings(root.catalog[root.selectedIndex])) {
        root.configureWidget(root.catalog[root.selectedIndex])
        return true
      }
      return false
    }

    return false
  }

  onVisibleChanged: if (visible) {
    root.view = "slots"
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildApps()
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }
  onViewChanged: {
    if (root.view === "opens" || root.view === "dock-add") {
      root.filterText = ""
      root.selectedIndex = 0
      root.rebuildApps()
    }
    if (root.view === "widgets" || root.view === "dock" || root.view === "edit" || root.view === "slots")
      if (root.selectedIndex < 0) root.selectedIndex = 0
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }
  onActiveTileChanged: if (root.view === "panel") root.pushPanelSettings()

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.visible) root.rebuildApps() }
  }

  function rowFill(selected, hovered) {
    if (selected) return root.selectedBackground
    if (hovered) return root.hoverFill
    return "transparent"
  }


  // Gear beside a slot or widget that ships Settings.qml.
  component SettingsGear: Item {
    id: gear
    signal triggered()
    z: 2
    width: Style.space(40)
    height: Style.space(40)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: ""
      color: gearMouse.containsMouse ? root.selectedText : root.foreground
      opacity: gearMouse.containsMouse ? 1 : 0.72
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: gearMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: gear.triggered()
    }
  }

  // Shared focus-ring row chrome.
  component NavRow: BorderSurface {
    id: navRow
    property bool selected: false
    property bool hovered: false
    width: parent ? parent.width : 0
    height: Style.space(56)
    radius: root.cornerRadius
    color: root.rowFill(selected, hovered)
    borderSpec: selected ? root.borderSpec : Border.none()
  }

  BorderSurface {
    id: sheet
    anchors.left: parent.left
    anchors.top: parent.top
    width: root.fitPanel ? Math.min(parent.width, root.fittedWidth) : parent.width
    height: root.fitPanel ? Math.min(parent.height, root.fittedHeight)
                          : (root.hostHeight > 0 ? Math.max(root.hostHeight, parent.height) : parent.height)
    radius: root.cornerRadius
    color: Color.menu.background
    borderSpec: root.borderSpec
  }
  MouseArea { anchors.fill: parent; onClicked: {} }

  Item {
    id: keyScope
    anchors.left: sheet.left
    anchors.right: sheet.right
    anchors.top: sheet.top
    anchors.bottom: sheet.bottom
    anchors.margins: root.contentMargin
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: function(event) {
      if (event.key === Qt.Key_Escape) event.accepted = true
      else if (root.view !== "opens" && root.view !== "dock-add" && root.view !== "webapp"
               && (event.key === Qt.Key_J || event.key === Qt.Key_K
                   || event.key === Qt.Key_Up || event.key === Qt.Key_Down
                   || event.key === Qt.Key_Return || event.key === Qt.Key_Enter))
        event.accepted = true
    }
    Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.right: doneButton.left
      anchors.rightMargin: Style.spacing.md
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.titleForView()
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
      text: root.view === "slots" ? "Done" : "Back"
      fontFamily: root.fontFamily
      foreground: root.foreground
      bordered: true
      onClicked: root.handleEscape()
    }

    Text {
      id: hintText
      visible: root.view === "slots" || root.view === "edit" || root.view === "dock"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.space(6)
      textFormat: Text.PlainText
      text: root.view === "dock"
            ? "j/k move · Enter add · h/l reorder · x remove · Esc back"
            : root.view === "edit"
              ? "j/k move · Enter open · g widget settings · Esc back"
              : "j/k or arrows move · Enter open · Esc close"
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    // —— Home: slots + icon dock ——
    ListView {
      id: homeList
      visible: root.view === "slots"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: hintText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.homeCount
      currentIndex: root.selectedIndex
      highlightFollowsCurrentItem: true
      keyNavigationEnabled: false

      delegate: NavRow {
        required property int index
        readonly property bool isDock: index === root.slotCount
        readonly property var tile: isDock ? null : (root.resolvedTiles[index] || { empty: true })
        readonly property bool empty: !isDock && tile.empty === true
        selected: index === root.selectedIndex
        hovered: rowMouse.containsMouse
        width: ListView.view.width

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(22)
          textFormat: Text.PlainText
          text: isDock ? "󰖟" : String(index + 1)
          color: parent.selected ? root.selectedText : root.foreground
          opacity: parent.selected ? 1 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(40)
          anchors.right: slotGear.visible ? slotGear.left : parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: isDock ? "Icon dock" : (empty ? "Empty slot" : String(tile.widgetName || "Icon & link"))
            color: parent.parent.selected ? root.selectedText : root.foreground
            opacity: empty && !isDock ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: isDock
                  ? (root.dockCount === 0 ? "Small icon launchers under the grid" : (root.dockCount + " icon" + (root.dockCount === 1 ? "" : "s")))
                  : (empty ? "Widget + what it opens" : ("Opens " + root.opensLabel(tile)))
            color: parent.parent.selected ? root.selectedText : root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        SettingsGear {
          id: slotGear
          visible: !isDock && root.hasSettings(tile)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          onTriggered: root.openPanel(index, "slots")
        }

        MouseArea {
          id: rowMouse
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: slotGear.visible ? slotGear.left : parent.right
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: {
            root.selectedIndex = index
            root.activateHome()
          }
        }
      }
    }

    // —— Edit slot ——
    Column {
      visible: root.view === "edit"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: hintText.bottom
      anchors.topMargin: Style.spacing.lg
      spacing: Style.spacing.md

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "The widget is what you see. Opens is what a click launches — they are separate."
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      NavRow {
        width: parent.width
        selected: root.selectedIndex === 0
        hovered: widgetRowMouse.containsMouse
        Column {
          anchors.left: parent.left
          anchors.right: editGear.visible ? editGear.left : parent.right
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: "Widget"
            color: root.selectedIndex === 0 ? root.selectedText : root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: String(activeTile.widgetName || "Icon & link")
            color: root.selectedIndex === 0 ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
            width: parent.width
          }
        }
        SettingsGear {
          id: editGear
          visible: root.hasSettings(activeTile)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          onTriggered: root.openPanel(root.activeIndex, "edit")
        }
        MouseArea {
          id: widgetRowMouse
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: editGear.visible ? editGear.left : parent.right
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = 0
          onClicked: { root.selectedIndex = 0; root.activateEdit() }
        }
      }

      NavRow {
        width: parent.width
        selected: root.selectedIndex === 1
        hovered: opensRowMouse.containsMouse
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: "Opens"
            color: root.selectedIndex === 1 ? root.selectedText : root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: root.opensLabel(activeTile)
            color: root.selectedIndex === 1 ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
            width: parent.width
          }
        }
        MouseArea {
          id: opensRowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = 1
          onClicked: { root.selectedIndex = 1; root.activateEdit() }
        }
      }

      NavRow {
        width: parent.width
        selected: root.selectedIndex === 2
        hovered: clearRowMouse.containsMouse
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Clear slot"
          color: root.selectedIndex === 2 ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
        MouseArea {
          id: clearRowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = 2
          onClicked: { root.selectedIndex = 2; root.activateEdit() }
        }
      }
    }

    // —— Widget catalog ——
    ListView {
      visible: root.view === "widgets"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      model: root.catalog.length
      currentIndex: root.selectedIndex

      delegate: NavRow {
        required property int index
        readonly property var modelData: root.catalog[index] || {}
        selected: index === root.selectedIndex
        hovered: false
        height: Style.space(62)
        width: ListView.view.width

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          textFormat: Text.PlainText
          text: String(modelData.icon || "󰣆")
          color: parent.selected ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(40)
          anchors.right: catalogGear.visible ? catalogGear.left : parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData.name || "")
            color: parent.parent.selected ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData.description || "")
            color: parent.parent.selected ? root.selectedText : root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        SettingsGear {
          id: catalogGear
          visible: root.hasSettings(modelData)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          onTriggered: root.configureWidget(modelData)
        }
        MouseArea {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: catalogGear.visible ? catalogGear.left : parent.right
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.chooseWidget(modelData)
        }
      }
    }

    // —— App search (opens + dock-add) ——
    Text {
      id: searchText
      visible: root.view === "opens" || root.view === "dock-add"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText
            : (root.view === "dock-add" ? "Type to search apps for the dock…" : "Type to search apps to open…")
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    ListView {
      visible: root.view === "opens" || root.view === "dock-add"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      model: root.appCount + 1
      currentIndex: root.selectedIndex

      delegate: NavRow {
        required property int index
        readonly property bool isNew: index === 0
        readonly property var row: isNew ? null : (root.appRows[index - 1] || null)
        selected: index === root.selectedIndex
        height: Style.space(50)
        width: ListView.view.width

        Text {
          visible: isNew
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "+ New web app"
          color: parent.selected ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Image {
          id: appIcon
          visible: !isNew
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          height: Style.font.iconLarge
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          asynchronous: true
          source: visible && root.desktopApps && row ? root.desktopApps.iconSource(row.iconName) : ""
        }
        Text {
          visible: !isNew
          anchors.left: parent.left
          anchors.leftMargin: Style.space(44)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row ? String(row.name || "") : ""
          color: parent.selected ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: {
            root.selectedIndex = index
            if (isNew) {
              root.panelReturn = root.view === "dock-add" ? "dock" : "edit"
              root.view = "webapp"
              Qt.callLater(function() { nameField.forceActiveFocus() })
            } else {
              root.chooseLaunch(TileModel.fromAppRow(row))
            }
          }
        }
      }
    }

    // —— Dock editor ——
    ListView {
      visible: root.view === "dock"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: hintText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.dockNavCount
      currentIndex: root.selectedIndex

      delegate: NavRow {
        required property int index
        readonly property bool isAdd: index === 0
        readonly property var item: isAdd ? null : (root.resolvedDock[index - 1] || { empty: true })
        selected: index === root.selectedIndex
        hovered: dockMouse.containsMouse
        height: Style.space(52)
        width: ListView.view.width

        Text {
          visible: isAdd
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "+ Add app"
          color: parent.selected ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Image {
          id: dockRowIcon
          visible: !isAdd
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          height: Style.font.iconLarge
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          asynchronous: true
          source: {
            if (isAdd || !item) return ""
            if (root.desktopApps && item.iconName)
              return root.desktopApps.iconSource(item.iconName)
            return String(item.faviconUrl || item.faviconFallbackUrl || "")
          }
        }
        Text {
          visible: !isAdd && dockRowIcon.status !== Image.Ready
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: item && item.icon ? item.icon : "󰣆"
          color: parent.selected ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Text {
          visible: !isAdd
          anchors.left: parent.left
          anchors.leftMargin: Style.space(44)
          anchors.right: dockHint.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.dockLabel(item)
          color: parent.selected ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }
        Text {
          id: dockHint
          visible: !isAdd && parent.selected
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "h/l reorder · x remove"
          color: root.selectedText
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          id: dockMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: {
            root.selectedIndex = index
            if (isAdd) root.activateDock()
          }
        }
      }
    }

    // —— New web app ——
    Column {
      visible: root.view === "webapp"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.lg
      spacing: Style.spacing.md
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "This is only what a click opens. It does not change the widget."
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      TextField {
        id: nameField
        width: parent.width
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        placeholderText: "Name"
        text: root.webName
        onTextChanged: root.webName = text
      }
      TextField {
        id: urlField
        width: parent.width
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        placeholderText: "https://…"
        text: root.webUrl
        onTextChanged: root.webUrl = text
        onAccepted: root.createWebApp()
      }
      Button {
        text: "Use this site"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.createWebApp()
      }
    }

    Loader {
      id: settingsLoader
      visible: root.view === "panel"
      active: root.view === "panel" && root.activeSettingsSource.length > 0
      anchors.left: parent.left
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      width: item && item.implicitWidth > 0 ? item.implicitWidth : parent.width
      height: item && item.implicitHeight > 0 ? item.implicitHeight : Math.max(0, parent.height - y)
      source: root.activeSettingsSource
      onLoaded: {
        if (!item) return
        root.panelHasSettings = ("settings" in item)
        if ("host" in item) item.host = { save: function(settings) { root.writeSettings(settings) } }
        if ("fontFamily" in item) item.fontFamily = root.fontFamily
        if ("foreground" in item) item.foreground = root.foreground
        if ("hoverFill" in item) item.hoverFill = root.hoverFill
        if ("borderSpec" in item) item.borderSpec = root.borderSpec
        if ("cornerRadius" in item) item.cornerRadius = root.cornerRadius
        root.pushPanelSettings()
      }
      onStatusChanged: if (status !== Loader.Ready) root.panelHasSettings = false
    }

    Connections {
      target: settingsLoader.item
      enabled: root.panelHasSettings
      function onSettingsChanged() {
        if (root.applyingSettings || !settingsLoader.item) return
        root.writeSettings(settingsLoader.item.settings)
      }
    }
  }
}
