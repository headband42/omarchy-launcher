import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

// Launcher settings. Home is the slots laid out as the grid they are on
// screen, with the icon dock under them. A slot opens to its widget, that
// widget's own settings, and what a click opens. Keyboard first: arrows move,
// Enter picks, Esc backs out, digits jump to a slot, and the footer names the
// keys for the view. Moving the pointer moves the same cursor, and a click
// does what Enter would.
Item {
  id: root
  // Settings owns the keyboard while open: Menu hides the card (and keyCatcher)
  // behind settingsHidesChrome, so focus must land on keyScope — not this Item alone.
  focus: true
  Keys.forwardTo: [keyScope]

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

  // —— Sizes. Every view but a widget's own panel shares one width, so the
  // sheet does not jump sideways between them. Lists that can run long get a
  // fixed height and scroll, so typing a search does not resize the sheet.
  readonly property int preferredWidth: Style.space(720)
  readonly property int gap: Style.spacing.xxl
  readonly property int gridGap: Style.spacing.lg
  readonly property int cellHeight: Style.space(112)
  readonly property int dockCardHeight: Style.space(60)
  readonly property int rowHeight: Style.space(54)
  readonly property int pickRowHeight: Style.space(38)
  readonly property int sectionRowHeight: Style.space(30)
  readonly property int appRowHeight: Style.space(46)
  readonly property int searchHeight: Style.space(40)
  readonly property int listSpacing: Style.spacing.xxs
  readonly property int scrollHeight: Style.space(500)
  readonly property int cellWidth: Math.max(0, Math.floor((body.width - (root.columns - 1) * root.gridGap) / Math.max(1, root.columns)))
  readonly property int gridHeight: root.rows * root.cellHeight + Math.max(0, root.rows - 1) * root.gridGap

  function listHeight(count, rowH) {
    var n = Math.max(0, count)
    if (n <= 0) return 0
    return n * rowH + Math.max(0, n - 1) * root.listSpacing
  }

  readonly property int bodyHeight: {
    if (root.view === "slots") return root.gridHeight + root.gridGap + root.dockCardHeight
    if (root.view === "edit") return root.listHeight(root.editRows.length, root.rowHeight)
    if (root.view === "widgets" || root.view === "opens" || root.view === "dock-add")
      return root.searchHeight + root.gap + root.scrollHeight
    if (root.view === "dock") return Math.min(root.listHeight(root.dockNavCount, root.rowHeight), root.scrollHeight)
    if (root.view === "webapp") return webForm.implicitHeight
    return Style.space(200)
  }
  readonly property int preferredHeight: Math.ceil(root.contentMargin * 2 + header.height + root.gap + root.bodyHeight
      + (footer.visible ? root.gap + footer.height : 0))

  readonly property int slotCount: Math.max(0, root.columns * root.rows)
  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.desktopApps, root.widgetCatalog, root.widgetSettings)
  }

  // slots | edit | widgets | opens | webapp | panel | dock | dock-add
  property string view: "slots"
  property int activeIndex: 0
  property string panelReturn: "edit"
  property string filterText: ""
  property int selectedIndex: 0
  // The home column to land on when coming up out of the dock row.
  property int homeColumn: 0
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
  // Dock list: "Add an app" then each icon.
  readonly property int dockNavCount: root.dockCount + 1
  // The Space hint letters Menu gives the dock icons, in order.
  readonly property var dockHintLetters: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]

  // The slot editor's rows. Settings only when the widget has a panel, and
  // Clear only when there is something to clear.
  readonly property var editRows: {
    var list = ["widget"]
    if (root.hasSettings(root.activeTile)) list.push("settings")
    list.push("opens")
    if (root.activeTile.empty !== true) list.push("clear")
    return list
  }

  // The picker's rows: headers and widgets, or search hits. pickRowIndex maps
  // a pick (what selectedIndex counts) to its row.
  readonly property var pickRows: TileModel.pickerRows(root.widgetCatalog, root.view === "widgets" ? root.filterText : "")
  readonly property var pickRowIndex: {
    var out = []
    for (var i = 0; i < root.pickRows.length; i++) {
      if (root.pickRows[i].kind === "widget") out.push(i)
    }
    return out
  }
  readonly property int pickCount: root.pickRowIndex.length
  readonly property int widgetTotal: Math.max(0, TileModel.withIconLink(root.widgetCatalog).length - 1)
  readonly property var pickedWidget: {
    var row = root.pickRows[root.pickRowIndex[root.selectedIndex]]
    return row ? row.widget : null
  }
  readonly property string currentWidgetId: root.activeTile.empty === true ? "\u0000" : String(root.activeTile.widget || "")

  readonly property bool searchView: root.view === "widgets" || root.view === "opens" || root.view === "dock-add"

  readonly property bool fitPanel: root.view === "panel"
      && settingsLoader.status === Loader.Ready
      && settingsLoader.item
      && settingsLoader.item.implicitWidth > 0
      && settingsLoader.item.implicitHeight > 0
  readonly property int fittedWidth: {
    if (!root.fitPanel) return 0
    var pad = root.contentMargin * 2
    var content = settingsLoader.item.implicitWidth + pad
    var title = crumbBar.implicitWidth + doneButton.implicitWidth + root.gap + pad
    return Math.ceil(Math.max(content, title))
  }
  readonly property int fittedHeight: {
    if (!root.fitPanel) return 0
    var pad = root.contentMargin * 2
    return Math.ceil(pad + header.height + root.gap + settingsLoader.item.implicitHeight)
  }

  // —— Colors on top of the menu's own.
  readonly property color cardFill: Util.alpha(root.foreground, 0.035)
  readonly property var cardBorder: Border.flat(Util.alpha(root.foreground, 0.1), Math.max(1, Style.space(1)))
  readonly property var cursorBorder: root.borderSpec
  readonly property color dangerColor: Color.urgent

  // —— Glyphs (nerd font, in the menu font).
  readonly property string glyphGear: ""
  readonly property string glyphSearch: ""
  readonly property string glyphPlus: ""
  readonly property string glyphCheck: ""
  readonly property string glyphTrash: ""
  readonly property string glyphUp: ""
  readonly property string glyphDown: ""
  readonly property string glyphRemove: ""
  readonly property string glyphGlobe: ""
  readonly property string glyphLink: ""
  readonly property string glyphWeb: "󰖟"
  readonly property string glyphWidget: "󰣆"
  readonly property string glyphDock: "󱂩"

  // ——————————————————————————————————————————————— navigation

  function back() {
    if (root.view === "panel") {
      var target = root.panelReturn || "edit"
      root.go(target, target === "slots" ? root.activeIndex : root.editRowOf("settings"))
      return true
    }
    if (root.view === "dock-add") { root.go("dock", 0); return true }
    if (root.view === "dock") { root.go("slots", root.slotCount); return true }
    if (root.view === "webapp") {
      if (root.panelReturn === "dock") root.go("dock-add", 0)
      else root.go("opens", 0)
      root.panelReturn = "edit"
      return true
    }
    if (root.view === "widgets") { root.go("edit", root.editRowOf("widget")); return true }
    if (root.view === "opens") { root.go("edit", root.editRowOf("opens")); return true }
    if (root.view === "edit") { root.go("slots", root.activeIndex); return true }
    root.closed()
    return true
  }

  // Esc: a panel gets it first, a search clears before it backs out.
  function handleEscape() {
    if (root.view === "panel" && settingsLoader.item && settingsLoader.item.handleEscape
        && settingsLoader.item.handleEscape())
      return true
    if (root.searchView && root.filterText) {
      root.setFilter("")
      return true
    }
    return root.back()
  }

  function go(next, selection) {
    pointerGate.reset()
    root.view = next
    root.selectedIndex = Math.max(0, selection || 0)
    if (next === "slots" && root.selectedIndex < root.slotCount)
      root.homeColumn = root.selectedIndex % Math.max(1, root.columns)
    root.revealSelection()
    Qt.callLater(root.takeFocus)
  }

  // A breadcrumb click.
  function goTo(target) {
    if (target === root.view) return
    if (target === "panel-root") {
      if (settingsLoader.item && settingsLoader.item.handleEscape) settingsLoader.item.handleEscape()
      return
    }
    if (target === "slots") {
      var onDock = root.view === "dock" || root.view === "dock-add" || (root.view === "webapp" && root.panelReturn === "dock")
      root.go("slots", onDock ? root.slotCount : root.activeIndex)
    } else if (target === "edit") {
      root.go("edit", 0)
    } else if (target === "widgets") {
      root.openPicker()
    } else {
      root.go(target, 0)
    }
  }

  function crumbsForView() {
    if (root.view === "slots") return [{ label: "Launcher settings", view: "slots" }]
    var top = { label: "Settings", view: "slots" }
    var slot = { label: "Slot " + (root.activeIndex + 1), view: "edit" }
    var dockCrumb = { label: "Icon dock", view: "dock" }
    if (root.view === "edit") return [top, slot]
    if (root.view === "widgets") return [top, slot, { label: "Widget", view: "widgets" }]
    if (root.view === "opens") return [top, slot, { label: "Opens", view: "opens" }]
    if (root.view === "dock") return [top, dockCrumb]
    if (root.view === "dock-add") return [top, dockCrumb, { label: "Add", view: "dock-add" }]
    if (root.view === "webapp") {
      if (root.panelReturn === "dock")
        return [top, dockCrumb, { label: "Add", view: "dock-add" }, { label: "Web app", view: "webapp" }]
      return [top, slot, { label: "Opens", view: "opens" }, { label: "Web app", view: "webapp" }]
    }
    if (root.view === "panel") {
      var custom = settingsLoader.item ? String(settingsLoader.item.panelTitle || "") : ""
      var name = String((root.activeTile && root.activeTile.widgetName) || "Widget")
      var list = root.panelReturn === "slots" ? [top] : [top, slot]
      list.push({ label: name, view: custom ? "panel-root" : "panel" })
      if (custom) list.push({ label: custom, view: "panel" })
      return list
    }
    return [top]
  }

  readonly property var crumbList: root.crumbsForView()

  // [keys, what they do] for the footer.
  function hintsForView() {
    var digits = "1–" + root.slotCount
    var esc = ["esc", root.searchView && root.filterText ? "clear search" : "back"]
    if (root.view === "slots") {
      var list = [["←↑↓→", "move"], [digits, "open slot"], ["⏎", "edit"]]
      if (root.selectedIndex < root.slotCount && root.hasSettings(root.resolvedTiles[root.selectedIndex]))
        list.push(["g", "widget settings"])
      list.push(["esc", "close"])
      return list
    }
    if (root.view === "edit") {
      var edit = [["↑↓", "move"], ["⏎", "choose"]]
      if (root.hasSettings(root.activeTile)) edit.push(["g", "widget settings"])
      edit.push([digits, "other slot"])
      edit.push(esc)
      return edit
    }
    if (root.view === "widgets") {
      var pick = [["type", "search"], ["↑↓", "move"], ["⏎", "use"]]
      if (root.hasSettings(root.pickedWidget)) pick.push(["shift ⏎", "use and set up"])
      pick.push(esc)
      return pick
    }
    if (root.view === "opens" || root.view === "dock-add")
      return [["type", "search"], ["↑↓", "move"], ["⏎", root.view === "dock-add" ? "add" : "choose"], esc]
    if (root.view === "dock") {
      if (root.selectedIndex === 0) return [["↑↓", "move"], ["⏎", "add an app"], esc]
      return [["↑↓", "move"], ["shift ↑↓", "reorder"], ["del", "remove"], esc]
    }
    if (root.view === "webapp") return [["tab", "next field"], ["⏎", "add"], ["esc", "back"]]
    return []
  }

  function hasSettings(entry) {
    return !!(entry && String(entry.settingsQml || "").length > 0)
  }

  function editRowOf(kind) {
    var at = root.editRows.indexOf(kind)
    return at < 0 ? 0 : at
  }

  function openPanel(index, returnView) {
    root.activeIndex = index
    root.panelReturn = returnView || "edit"
    if (!root.hasSettings(root.resolvedTiles[index])) return
    root.go("panel", 0)
  }

  function openPicker() {
    root.go("widgets", 0)
    root.selectedIndex = TileModel.pickOf(root.pickRows, root.currentWidgetId)
    Qt.callLater(function() {
      var row = root.pickRowIndex[root.selectedIndex]
      if (row !== undefined && row > 1) widgetList.positionViewAtIndex(row, ListView.Center)
    })
  }

  // Put a widget on the active slot. With `configure`, go straight on to its
  // panel; otherwise back to the slot, on its Settings row when it has one.
  function useWidget(widget, configure) {
    if (!widget) return
    var current = root.slotAt(root.activeIndex)
    var nextId = String(widget.id || "")
    if (nextId !== TileModel.widgetId(current) || TileModel.isEmptyTile(current))
      root.writeSlot(root.activeIndex, TileModel.applyWidget(current, widget, root.widgetSettings))
    if (configure && root.hasSettings(widget)) {
      root.panelReturn = "edit"
      root.go("panel", 0)
      return
    }
    root.go("edit", 0)
    Qt.callLater(function() { root.selectedIndex = root.editRowOf(root.hasSettings(widget) ? "settings" : "widget") })
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

  function persist(next) { root.saveTiles(next, root.widgetSettings) }

  function persistDock(next) {
    root.saveDock(TileModel.storedDock(next))
  }

  function addDockItem(launch) {
    if (!launch) return
    var item = TileModel.storedDockItem(launch)
    if (!item) return
    var next = TileModel.storedDock(root.dockList)
    next.push(item)
    root.persistDock(next)
    root.go("dock", next.length)
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
    root.revealSelection()
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
    if (index < 0 || index >= root.slotCount) return
    root.activeIndex = index
    root.go("edit", 0)
  }

  function chooseLaunch(launch) {
    if (root.view === "dock-add" || (root.view === "webapp" && root.panelReturn === "dock")) {
      root.panelReturn = "edit"
      root.addDockItem(launch)
      return
    }
    root.writeSlot(root.activeIndex, TileModel.applyLaunch(root.slotAt(root.activeIndex), launch))
    root.panelReturn = "edit"
    root.go("edit", 0)
    Qt.callLater(function() { root.selectedIndex = root.editRowOf("opens") })
  }

  function clearSlot() {
    root.writeSlot(root.activeIndex, null)
    root.go("slots", root.activeIndex)
  }

  function rebuildApps() {
    var _rev = root.catalogRevision
    var rows = root.desktopApps ? root.desktopApps.list(root.filterText) : []
    root.appRows = rows
    root.appCount = rows.length
    if (root.selectedIndex >= rows.length + 1) root.selectedIndex = Math.max(0, rows.length)
  }

  function setFilter(next) {
    pointerGate.reset()
    root.filterText = next
    root.selectedIndex = 0
    if (root.view !== "widgets") root.rebuildApps()
    root.revealSelection()
  }

  function openWebForm() {
    root.panelReturn = root.view === "dock-add" ? "dock" : "edit"
    root.go("webapp", 0)
    Qt.callLater(function() { nameField.forceActiveFocus() })
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
    return TileModel.launchLabel(tile) || "Nothing yet"
  }

  // What a slot looks like in the settings: the widget's glyph, or for Icon &
  // link the icon of what it opens.
  function widgetGlyph(tile) {
    if (!tile || tile.empty === true) return root.glyphPlus
    if (!tile.widget) return String(tile.icon || root.glyphWeb)
    var meta = TileModel.findWidget(root.widgetCatalog, tile.widget)
    return String((meta && meta.icon) || root.glyphWidget)
  }

  function launchImage(tile) {
    if (!tile || tile.empty === true) return ""
    if (tile.iconName && root.desktopApps) return String(root.desktopApps.iconSource(tile.iconName) || "")
    return String(tile.faviconUrl || "")
  }

  function step(delta, count, wrap) {
    if (count <= 0) return
    pointerGate.reset()
    var next = root.selectedIndex + delta
    if (wrap) next = ((next % count) + count) % count
    else next = Math.max(0, Math.min(count - 1, next))
    root.selectedIndex = next
    root.revealSelection()
  }

  function homeStep(dx, dy) {
    pointerGate.reset()
    var next = TileModel.homeMove(root.selectedIndex, dx, dy, root.columns, root.rows, root.homeColumn)
    if (next < root.slotCount) root.homeColumn = next % Math.max(1, root.columns)
    root.selectedIndex = next
  }

  // A real pointer move over a row moves the cursor there. A row sliding
  // under a still pointer (the list scrolled from the keyboard) does not.
  function pointerSelect(item, mouse, index) {
    if (!pointerGate.moved(item, mouse)) return
    root.selectedIndex = index
  }

  function revealSelection() { Qt.callLater(root.revealNow) }

  function revealNow() {
    if (root.view === "widgets") {
      var row = root.pickRowIndex[root.selectedIndex]
      if (row === undefined) return
      if (row <= 1) { widgetList.positionViewAtBeginning(); return }
      var header = root.pickRows[row - 1] && root.pickRows[row - 1].kind === "header"
      root.revealIn(widgetList, header ? row - 1 : row)
      root.revealIn(widgetList, row)
    } else if (root.view === "opens" || root.view === "dock-add") {
      root.revealIn(appList, root.selectedIndex)
    } else if (root.view === "dock") {
      root.revealIn(dockListView, root.selectedIndex)
    }
  }

  // Contain alone parks the row flush with the edge, under the fade. Leave
  // room for the fade past it, so the row and a hint of the next both show.
  function revealIn(list, index) {
    list.positionViewAtIndex(index, ListView.Contain)
    var item = list.itemAtIndex(index)
    if (!item) return
    var reach = Style.space(22)
    var maxY = Math.max(list.originY, list.originY + list.contentHeight - list.height)
    var over = item.y + item.height + reach - (list.contentY + list.height)
    if (over > 0) list.contentY = Math.min(list.contentY + over, maxY)
    var under = list.contentY - (item.y - reach)
    if (under > 0) list.contentY = Math.max(list.contentY - under, list.originY)
  }

  function digitOf(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return 0
    if (event.text && event.text.length === 1 && event.text >= "1" && event.text <= "9")
      return event.text.charCodeAt(0) - 48
    return 0
  }

  function isLetter(event, letter) {
    return event.text === letter && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier)
  }
  function isNavUp(event) {
    return (event.key === Qt.Key_Up && !(event.modifiers & Qt.ShiftModifier)) || root.isLetter(event, "k")
  }
  function isNavDown(event) {
    return (event.key === Qt.Key_Down && !(event.modifiers & Qt.ShiftModifier)) || root.isLetter(event, "j")
  }
  function isActivate(event) {
    return event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
  }
  function isTyping(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
  }

  function activateHome() {
    if (root.selectedIndex >= 0 && root.selectedIndex < root.slotCount) {
      root.openSlot(root.selectedIndex)
      return
    }
    if (root.selectedIndex === root.slotCount) root.go("dock", 0)
  }

  function activateEdit() {
    var kind = root.editRows[root.selectedIndex]
    if (kind === "widget") root.openPicker()
    else if (kind === "settings") root.openPanel(root.activeIndex, "edit")
    else if (kind === "opens") root.go("opens", 0)
    else if (kind === "clear") root.clearSlot()
  }

  function activateApp(index) {
    root.selectedIndex = index
    if (index === 0) root.openWebForm()
    else root.chooseLaunch(TileModel.fromAppRow(root.appRows[index - 1]))
  }

  function handleKey(event) {
    if (root.view === "panel") {
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left || event.key === Qt.Key_Backspace)
        return root.handleEscape()
      if (settingsLoader.item && settingsLoader.item.handleKey)
        return !!settingsLoader.item.handleKey(event)
      return false
    }

    if (event.key === Qt.Key_Escape) { root.handleEscape(); return true }

    if (root.view === "webapp") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.createWebApp(); return true }
      return false
    }

    if (root.view === "slots") {
      if (root.isNavUp(event)) { root.homeStep(0, -1); return true }
      if (root.isNavDown(event)) { root.homeStep(0, 1); return true }
      if (event.key === Qt.Key_Left || root.isLetter(event, "h")) { root.homeStep(-1, 0); return true }
      if (event.key === Qt.Key_Right || root.isLetter(event, "l")) { root.homeStep(1, 0); return true }
      if (event.key === Qt.Key_Tab) { root.homeStep(1, 0); return true }
      if (event.key === Qt.Key_Backtab) { root.homeStep(-1, 0); return true }
      if (root.isActivate(event)) { root.activateHome(); return true }
      var homeDigit = root.digitOf(event)
      if (homeDigit >= 1 && homeDigit <= root.slotCount) { root.openSlot(homeDigit - 1); return true }
      if (root.isLetter(event, "g") && root.selectedIndex < root.slotCount) {
        if (root.hasSettings(root.resolvedTiles[root.selectedIndex])) root.openPanel(root.selectedIndex, "slots")
        return true
      }
      if (event.key === Qt.Key_Backspace) { root.back(); return true }
      return false
    }

    if (root.view === "edit") {
      if (root.isNavUp(event)) { root.step(-1, root.editRows.length, true); return true }
      if (root.isNavDown(event)) { root.step(1, root.editRows.length, true); return true }
      if (root.isActivate(event) || event.key === Qt.Key_Right || root.isLetter(event, "l")) { root.activateEdit(); return true }
      if (root.isLetter(event, "g")) {
        if (root.hasSettings(root.activeTile)) root.openPanel(root.activeIndex, "edit")
        return true
      }
      var editDigit = root.digitOf(event)
      if (editDigit >= 1 && editDigit <= root.slotCount) { root.openSlot(editDigit - 1); return true }
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace || root.isLetter(event, "h")) { root.back(); return true }
      return false
    }

    if (root.view === "dock") {
      var at = root.selectedIndex - 1
      if (event.key === Qt.Key_Up && (event.modifiers & Qt.ShiftModifier)) { root.moveDock(at, -1); return true }
      if (event.key === Qt.Key_Down && (event.modifiers & Qt.ShiftModifier)) { root.moveDock(at, 1); return true }
      if (root.isNavUp(event)) { root.step(-1, root.dockNavCount, true); return true }
      if (root.isNavDown(event)) { root.step(1, root.dockNavCount, true); return true }
      if (root.isActivate(event) || event.key === Qt.Key_Right) {
        if (root.selectedIndex === 0) root.go("dock-add", 0)
        return true
      }
      if (at >= 0) {
        if (event.key === Qt.Key_Delete || root.isLetter(event, "x")) { root.removeDockAt(at); return true }
        if (root.isLetter(event, "h") || event.text === "<") { root.moveDock(at, -1); return true }
        if (root.isLetter(event, "l") || event.text === ">") { root.moveDock(at, 1); return true }
      }
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) { root.back(); return true }
      return false
    }

    if (root.searchView) {
      var count = root.view === "widgets" ? root.pickCount : root.appCount + 1
      if (event.key === Qt.Key_Up) { root.step(-1, count, true); return true }
      if (event.key === Qt.Key_Down) { root.step(1, count, true); return true }
      if (event.key === Qt.Key_PageUp) { root.step(-8, count, false); return true }
      if (event.key === Qt.Key_PageDown) { root.step(8, count, false); return true }
      if (event.key === Qt.Key_Tab) { root.step(1, count, true); return true }
      if (event.key === Qt.Key_Backtab) { root.step(-1, count, true); return true }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.view === "widgets") root.useWidget(root.pickedWidget, !!(event.modifiers & Qt.ShiftModifier))
        else if (count > 0) root.activateApp(root.selectedIndex)
        return true
      }
      if (Util.editsFilter(event, root.filterText)) { root.setFilter(Util.editedFilter(event, root.filterText)); return true }
      if (!root.filterText && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left)) { root.back(); return true }
      if (root.isTyping(event) && !(event.text === " " && !root.filterText)) {
        root.setFilter(root.filterText + event.text)
        return true
      }
      return false
    }

    return false
  }

  // Menu (and callers) use this so keys work on first open, before any click.
  function takeFocus() {
    if (!root.visible) return
    if (root.view === "webapp" && (nameField.activeFocus || urlField.activeFocus)) return
    keyScope.forceActiveFocus()
  }

  onVisibleChanged: if (visible) {
    root.panelReturn = "edit"
    root.go("slots", 0)
    root.homeColumn = 0
    root.filterText = ""
    root.rebuildApps()
  }
  onViewChanged: {
    if (root.searchView) {
      root.filterText = ""
      if (root.view !== "widgets") root.rebuildApps()
    }
  }
  onActiveTileChanged: if (root.view === "panel") root.pushPanelSettings()

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.visible) root.rebuildApps() }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: sheet
  }

  // ———————————————————————————————————————————————— components

  // A key and what it does, for the footer.
  component KeyHint: Row {
    id: hint
    property string keys: ""
    property string label: ""
    spacing: Style.space(6)

    BorderSurface {
      anchors.verticalCenter: parent.verticalCenter
      width: keyText.implicitWidth + Style.space(12)
      height: keyText.implicitHeight + Style.space(4)
      radius: Math.min(root.cornerRadius, Style.space(4))
      color: Util.alpha(root.foreground, 0.07)
      borderSpec: Border.flat(Util.alpha(root.foreground, 0.2), Math.max(1, Style.space(1)))

      Text {
        id: keyText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: hint.keys
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: hint.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A small round button on a row or a card: the gear, or the dock's move
  // and remove. It takes its own clicks so they never reach the row.
  component IconAction: BorderSurface {
    id: action
    property string glyph: ""
    property bool shown: true
    property bool danger: false
    property bool dimmed: false
    signal triggered()

    width: Style.space(30)
    height: Style.space(30)
    radius: Math.min(root.cornerRadius, width / 2)
    color: actionMouse.containsMouse ? Util.alpha(action.danger ? root.dangerColor : root.foreground, 0.14) : "transparent"
    opacity: action.shown ? 1 : 0
    visible: opacity > 0

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: action.glyph
      color: action.danger && actionMouse.containsMouse ? root.dangerColor : root.foreground
      opacity: action.dimmed ? 0.25 : (actionMouse.containsMouse ? 1 : 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.shown && !action.dimmed
      cursorShape: Qt.PointingHandCursor
      onClicked: action.triggered()
    }
  }

  // An app's icon from the theme or a site's favicon, else a glyph.
  component LaunchIcon: Item {
    id: launchIcon
    property string source: ""
    property string glyph: ""
    property color tint: root.foreground
    property int glyphSize: Style.font.iconLarge
    property real glyphOpacity: 1

    Image {
      id: launchImage
      anchors.fill: parent
      visible: status === Image.Ready
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      asynchronous: true
      source: launchIcon.source
    }

    Text {
      anchors.centerIn: parent
      visible: !launchImage.visible
      textFormat: Text.PlainText
      text: launchIcon.glyph
      color: launchIcon.tint
      opacity: launchIcon.glyphOpacity
      font.family: root.fontFamily
      font.pixelSize: launchIcon.glyphSize
    }
  }

  // One row of a list: an icon, a title over a caption, and on the right a
  // check for the current choice, a dim glyph, trailing text, a chevron, and
  // any IconActions given as children.
  component SheetRow: BorderSurface {
    id: sheetRow
    property int rowIndex: 0
    property bool selected: false
    property string glyph: ""
    property string image: ""
    property string title: ""
    property string caption: ""
    property string trailing: ""
    property string badge: ""
    property bool chevron: false
    property bool checked: false
    property bool danger: false
    property bool muted: false
    property int iconSize: Style.font.iconLarge
    default property alias actions: actionRow.data
    readonly property color ink: sheetRow.danger && sheetRow.selected ? root.dangerColor
        : (sheetRow.selected ? root.selectedText : root.foreground)
    signal activated()

    height: root.rowHeight
    radius: root.cornerRadius
    color: sheetRow.selected ? root.selectedBackground : "transparent"
    borderSpec: sheetRow.selected ? root.cursorBorder : Border.none()

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: function(mouse) { root.pointerSelect(sheetRow, mouse, sheetRow.rowIndex) }
      onClicked: sheetRow.activated()
    }

    LaunchIcon {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: sheetRow.iconSize + Style.space(6)
      height: width
      source: sheetRow.image
      glyph: sheetRow.glyph
      tint: sheetRow.ink
      glyphSize: Math.round(sheetRow.iconSize * 1.25)
      glyphOpacity: sheetRow.muted ? 0.55 : 1
    }

    Column {
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(12)
      anchors.right: tail.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: sheetRow.title
        color: sheetRow.ink
        opacity: sheetRow.muted && !sheetRow.selected ? 0.6 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: sheetRow.caption.length > 0
        textFormat: Text.PlainText
        text: sheetRow.caption
        color: sheetRow.selected ? root.selectedText : root.foreground
        opacity: 0.58
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Row {
      id: tail
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Text {
        visible: sheetRow.checked
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.glyphCheck
        color: root.selectedText
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: sheetRow.badge.length > 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: sheetRow.badge
        color: sheetRow.ink
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: sheetRow.trailing.length > 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: sheetRow.trailing
        color: sheetRow.ink
        opacity: sheetRow.selected ? 0.85 : 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        id: actionRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
      }

      Text {
        visible: sheetRow.chevron
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "›"
        color: sheetRow.ink
        opacity: sheetRow.selected ? 0.85 : 0.35
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }
    }
  }

  // The search line of a picker. Keys go to the sheet, not to a text field,
  // so arrows and Enter keep working while it shows what was typed.
  component SearchBox: BorderSurface {
    id: search
    property string query: ""
    property string placeholder: ""
    property string note: ""

    height: root.searchHeight
    radius: root.cornerRadius
    color: Util.alpha(root.foreground, 0.05)
    borderSpec: Border.flat(Util.alpha(root.foreground, search.query ? 0.45 : 0.22), Math.max(1, Style.space(1)))

    Text {
      id: searchGlyph
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.glyphSearch
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: searchText
      anchors.left: searchGlyph.right
      anchors.leftMargin: Style.space(10)
      anchors.right: searchNote.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: search.query || search.placeholder
      color: root.foreground
      opacity: search.query ? 1 : 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideLeft
    }

    Rectangle {
      id: caret
      x: search.query ? searchText.x + Math.min(searchText.contentWidth, searchText.width) + Style.space(1)
                      : searchText.x - width - Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(1, Style.space(2))
      height: Style.font.title + Style.space(2)
      color: root.selectedText
      visible: search.visible

      SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: caret.visible
        NumberAnimation { to: 1; duration: 0 }
        PauseAnimation { duration: 530 }
        NumberAnimation { to: 0; duration: 0 }
        PauseAnimation { duration: 530 }
      }
    }

    Text {
      id: searchNote
      anchors.right: parent.right
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: search.note
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A thin bar on a list's right edge when it scrolls.
  component ScrollHint: Rectangle {
    property Flickable flick: null
    readonly property bool needed: !!flick && flick.contentHeight > flick.height + 1
    visible: needed
    width: Math.max(2, Style.space(3))
    radius: width / 2
    color: root.foreground
    opacity: 0.22
    x: flick ? flick.x + flick.width - width : 0
    y: flick ? flick.y + Math.max(0, flick.visibleArea.yPosition) * flick.height : 0
    height: flick ? Math.max(Style.space(24), Math.min(1, flick.visibleArea.heightRatio) * flick.height) : 0
  }

  // A fade at a list's edge while rows are hidden past it.
  component EdgeFade: Rectangle {
    property Flickable flick: null
    property bool atTop: true
    readonly property real hidden: !flick ? 0
        : (atTop ? flick.contentY - flick.originY
                 : flick.originY + flick.contentHeight - flick.height - flick.contentY)
    anchors.left: flick ? flick.left : undefined
    anchors.right: flick ? flick.right : undefined
    anchors.top: atTop && flick ? flick.top : undefined
    anchors.bottom: !atTop && flick ? flick.bottom : undefined
    height: Style.space(22)
    visible: opacity > 0
    opacity: flick && flick.contentHeight > flick.height ? Math.max(0, Math.min(1, hidden / height)) : 0
    gradient: Gradient {
      GradientStop { position: 0; color: atTop ? Color.menu.background : Util.alpha(Color.menu.background, 0) }
      GradientStop { position: 1; color: atTop ? Util.alpha(Color.menu.background, 0) : Color.menu.background }
    }
  }

  // ———————————————————————————————————————————————— the sheet

  BorderSurface {
    id: sheet
    anchors.left: parent.left
    anchors.top: parent.top
    width: root.fitPanel ? Math.min(parent.width, root.fittedWidth) : parent.width
    height: root.fitPanel ? Math.min(parent.height, root.fittedHeight)
                          : Math.min(parent.height > 0 ? parent.height : root.preferredHeight, root.preferredHeight)
    radius: root.cornerRadius
    color: Color.menu.background
    borderSpec: root.borderSpec
  }
  MouseArea { anchors.fill: sheet; onClicked: {} }

  Item {
    id: keyScope
    anchors.fill: sheet
    anchors.margins: root.contentMargin
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: function(event) {
      if (event.key === Qt.Key_Escape) event.accepted = true
      else if (!root.searchView && root.view !== "webapp"
               && (event.key === Qt.Key_J || event.key === Qt.Key_K
                   || event.key === Qt.Key_Up || event.key === Qt.Key_Down
                   || event.key === Qt.Key_Return || event.key === Qt.Key_Enter))
        event.accepted = true
    }
    Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }

    // —— Header: where you are, and the way out.
    Item {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Math.max(crumbBar.implicitHeight, doneButton.implicitHeight)

      Item {
        anchors.left: parent.left
        anchors.right: doneButton.left
        anchors.rightMargin: root.gap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        clip: true

        Row {
          id: crumbBar
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Repeater {
            model: root.crumbList

            Row {
              id: crumb
              required property int index
              required property var modelData
              readonly property bool last: index === root.crumbList.length - 1
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: String(crumb.modelData.label || "")
                color: crumbMouse.containsMouse ? root.selectedText : root.foreground
                opacity: crumb.last || crumbMouse.containsMouse ? 1 : 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.weight: crumb.last ? Font.Medium : Font.Normal

                MouseArea {
                  id: crumbMouse
                  anchors.fill: parent
                  enabled: !crumb.last
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.goTo(String(crumb.modelData.view || ""))
                }
              }

              Text {
                visible: !crumb.last
                textFormat: Text.PlainText
                text: "›"
                color: root.foreground
                opacity: 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
            }
          }
        }
      }

      Button {
        id: doneButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.view === "slots" ? "Done" : "Back"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.back()
      }
    }

    // —— Footer: the keys for this view.
    Row {
      id: footer
      visible: root.view !== "panel"
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      height: visible ? implicitHeight : 0
      spacing: Style.space(16)

      Repeater {
        model: root.hintsForView()
        KeyHint {
          required property var modelData
          keys: String(modelData[0])
          label: String(modelData[1])
        }
      }
    }

    // —— Body: one view at a time, between the header and the footer.
    Item {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      anchors.topMargin: root.gap
      anchors.bottom: footer.visible ? footer.top : parent.bottom
      anchors.bottomMargin: footer.visible ? root.gap : 0

      // —— Home: the slots as they sit on screen, and the dock under them.
      Item {
        id: homeView
        visible: root.view === "slots"
        anchors.fill: parent

        Repeater {
          model: root.slotCount

          BorderSurface {
            id: cell
            required property int index
            readonly property var tile: root.resolvedTiles[index] || { empty: true }
            readonly property bool empty: tile.empty === true
            readonly property bool selected: root.selectedIndex === index
            readonly property color ink: cell.selected ? root.selectedText : root.foreground

            x: (index % Math.max(1, root.columns)) * (root.cellWidth + root.gridGap)
            y: Math.floor(index / Math.max(1, root.columns)) * (root.cellHeight + root.gridGap)
            width: root.cellWidth
            height: root.cellHeight
            radius: root.cornerRadius
            color: cell.selected ? root.selectedBackground : root.cardFill
            borderSpec: cell.selected ? root.cursorBorder : root.cardBorder

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: function(mouse) {
                if (!pointerGate.moved(cell, mouse)) return
                root.selectedIndex = cell.index
                root.homeColumn = cell.index % Math.max(1, root.columns)
              }
              onClicked: root.openSlot(cell.index)
            }

            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.leftMargin: Style.space(10)
              anchors.topMargin: Style.space(7)
              textFormat: Text.PlainText
              text: String(cell.index + 1)
              color: cell.ink
              opacity: cell.selected ? 0.9 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Medium
            }

            IconAction {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(3)
              shown: root.hasSettings(cell.tile)
              glyph: root.glyphGear
              onTriggered: root.openPanel(cell.index, "slots")
            }

            LaunchIcon {
              id: cellArt
              anchors.horizontalCenter: parent.horizontalCenter
              y: Math.round(parent.height * 0.2)
              width: Math.round(Style.font.display * 1.4)
              height: width
              source: cell.tile.widget ? "" : root.launchImage(cell.tile)
              glyph: root.widgetGlyph(cell.tile)
              tint: cell.ink
              glyphSize: Math.round(Style.font.display * 1.4)
              glyphOpacity: cell.empty ? 0.35 : 1
            }

            Text {
              id: cellName
              anchors.top: cellArt.bottom
              anchors.topMargin: Style.space(8)
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: cell.empty ? "Empty" : String(cell.tile.widgetName || TileModel.ICON_LINK_NAME)
              color: cell.ink
              opacity: cell.empty ? 0.5 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.Medium
              elide: Text.ElideRight
            }

            Text {
              anchors.top: cellName.bottom
              anchors.topMargin: Style.space(2)
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: cell.empty ? "Pick a widget"
                    : (cell.tile.hasLaunch ? "Opens " + root.opensLabel(cell.tile) : "Opens nothing")
              color: cell.ink
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        BorderSurface {
          id: dockCard
          readonly property bool selected: root.selectedIndex === root.slotCount
          readonly property color ink: dockCard.selected ? root.selectedText : root.foreground
          y: root.gridHeight + root.gridGap
          width: parent.width
          height: root.dockCardHeight
          radius: root.cornerRadius
          color: dockCard.selected ? root.selectedBackground : root.cardFill
          borderSpec: dockCard.selected ? root.cursorBorder : root.cardBorder

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) { root.pointerSelect(dockCard, mouse, root.slotCount) }
            onClicked: root.go("dock", 0)
          }

          Text {
            id: dockGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.glyphDock
            color: dockCard.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
          }

          Column {
            anchors.left: dockGlyph.right
            anchors.leftMargin: Style.space(14)
            anchors.right: dockIcons.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Icon dock"
              color: dockCard.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.Medium
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.dockCount === 0 ? "App icons beside the settings button"
                    : (root.dockCount + (root.dockCount === 1 ? " icon" : " icons") + " beside the settings button")
              color: dockCard.ink
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Row {
            id: dockIcons
            anchors.right: dockChevron.left
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Repeater {
              model: Math.min(root.resolvedDock.length, 10)
              LaunchIcon {
                required property int index
                readonly property var item: root.resolvedDock[index] || ({})
                width: Style.space(24)
                height: width
                source: root.launchImage(item)
                glyph: String(item.icon || root.glyphWidget)
                tint: dockCard.ink
                glyphSize: Style.font.icon
              }
            }
          }

          Text {
            id: dockChevron
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "›"
            color: dockCard.ink
            opacity: dockCard.selected ? 0.85 : 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
        }
      }

      // —— One slot: its widget, the widget's settings, what it opens.
      Column {
        id: editView
        visible: root.view === "edit"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.listSpacing

        Repeater {
          model: root.editRows

          SheetRow {
            required property int index
            required property string modelData
            readonly property var tile: root.activeTile
            width: editView.width
            rowIndex: index
            selected: root.selectedIndex === index
            chevron: modelData !== "clear"
            danger: modelData === "clear"
            glyph: modelData === "widget" ? (tile.empty === true ? root.glyphWidget : (tile.widget ? root.widgetGlyph(tile) : root.glyphLink))
                 : modelData === "settings" ? root.glyphGear
                 : modelData === "opens" ? (tile.icon || root.glyphGlobe)
                 : root.glyphTrash
            image: modelData === "opens" ? root.launchImage(tile) : ""
            muted: (modelData === "widget" && tile.empty === true) || (modelData === "opens" && !tile.hasLaunch)
            title: modelData === "widget" ? (tile.empty === true ? "Choose a widget" : String(tile.widgetName || TileModel.ICON_LINK_NAME))
                 : modelData === "settings" ? "Widget settings"
                 : modelData === "opens" ? root.opensLabel(tile)
                 : "Clear slot"
            caption: modelData === "widget" ? "What the tile shows"
                   : modelData === "settings" ? "Options for " + String(tile.widgetName || "this widget")
                   : modelData === "opens" ? "What a click on the tile opens"
                   : "Remove the widget and what it opens"
            trailing: modelData === "widget" ? (tile.empty === true ? "Choose" : "Change")
                    : modelData === "opens" ? (tile.hasLaunch ? "Change" : "Choose")
                    : ""
            onActivated: {
              root.selectedIndex = index
              root.activateEdit()
            }
          }
        }
      }

      // —— The widget picker: search, sections, and the highlighted widget.
      Item {
        id: widgetsView
        visible: root.view === "widgets"
        anchors.fill: parent

        SearchBox {
          id: widgetSearch
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          visible: widgetsView.visible
          query: root.filterText
          placeholder: "Search " + root.widgetTotal + " widgets"
          note: root.filterText ? (root.pickCount === 1 ? "1 match" : root.pickCount + " matches") : ""
        }

        ListView {
          id: widgetList
          anchors.left: parent.left
          anchors.top: widgetSearch.bottom
          anchors.topMargin: root.gap
          anchors.bottom: parent.bottom
          width: Math.round(parent.width * 0.42)
          clip: true
          spacing: root.listSpacing
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.pickRows

          delegate: Item {
            id: pickDelegate
            required property int index
            required property var modelData
            readonly property bool isHeader: modelData.kind === "header"
            width: ListView.view.width - Style.space(8)
            height: isHeader ? root.sectionRowHeight : root.pickRowHeight

            Text {
              visible: pickDelegate.isHeader
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(5)
              textFormat: Text.PlainText
              text: String(pickDelegate.modelData.title || "").toUpperCase()
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: Style.space(1)
            }

            SheetRow {
              visible: !pickDelegate.isHeader
              anchors.fill: parent
              readonly property var widget: pickDelegate.modelData.widget || ({})
              rowIndex: pickDelegate.isHeader ? -1 : pickDelegate.modelData.pick
              selected: !pickDelegate.isHeader && root.selectedIndex === pickDelegate.modelData.pick
              iconSize: Style.font.icon
              glyph: String(widget.icon || root.glyphWidget)
              title: String(widget.name || widget.id || "")
              checked: String(widget.id || "") === root.currentWidgetId
              badge: root.hasSettings(widget) ? root.glyphGear : ""
              onActivated: root.useWidget(widget, false)
            }
          }
        }

        ScrollHint { flick: widgetList }
        EdgeFade { flick: widgetList; atTop: true }
        EdgeFade { flick: widgetList; atTop: false }

        BorderSurface {
          id: detail
          readonly property var widget: root.pickedWidget
          readonly property bool configurable: root.hasSettings(detail.widget)
          readonly property bool current: !!detail.widget && String(detail.widget.id || "") === root.currentWidgetId
          anchors.left: widgetList.right
          anchors.leftMargin: root.gap
          anchors.right: parent.right
          anchors.top: widgetList.top
          anchors.bottom: parent.bottom
          color: "transparent"

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(1, Style.space(1))
            color: Util.alpha(root.foreground, 0.1)
          }

          Text {
            visible: !detail.widget
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "No widget matches “" + root.filterText + "”"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          Column {
            visible: !!detail.widget
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Style.space(24)
            anchors.topMargin: Style.space(6)
            spacing: Style.space(12)
            clip: true
            height: Math.min(implicitHeight, parent.height - Style.space(6))

            Text {
              textFormat: Text.PlainText
              text: detail.widget ? String(detail.widget.icon || root.glyphWidget) : ""
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.displayLarge * 1.5)
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: detail.widget ? String(detail.widget.name || detail.widget.id || "") : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.weight: Font.Medium
              elide: Text.ElideRight
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: {
                  var tags = []
                  var category = TileModel.widgetCategory(detail.widget)
                  if (category) tags.push(category)
                  if (detail.configurable) tags.push(root.glyphGear + "  Has settings")
                  if (detail.current) tags.push(root.glyphCheck + "  On this slot")
                  return tags
                }

                BorderSurface {
                  required property string modelData
                  width: tagText.implicitWidth + Style.space(14)
                  height: tagText.implicitHeight + Style.space(6)
                  radius: Math.min(root.cornerRadius, height / 2)
                  color: Util.alpha(root.foreground, 0.06)
                  borderSpec: Border.flat(Util.alpha(root.foreground, 0.16), Math.max(1, Style.space(1)))

                  Text {
                    id: tagText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData
                    color: root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }

            Text {
              width: parent.width
              topPadding: Style.space(4)
              wrapMode: Text.WordWrap
              lineHeight: 1.25
              textFormat: Text.PlainText
              text: detail.widget ? String(detail.widget.description || "") : ""
              color: root.foreground
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              topPadding: Style.space(8)
              spacing: Style.space(8)

              Button {
                text: detail.current ? "Keep this widget" : "Use widget"
                fontFamily: root.fontFamily
                foreground: root.foreground
                bordered: true
                onClicked: root.useWidget(detail.widget, false)
              }

              Button {
                visible: detail.configurable
                text: "Use and set up"
                iconText: root.glyphGear
                fontFamily: root.fontFamily
                foreground: root.foreground
                bordered: true
                onClicked: root.useWidget(detail.widget, true)
              }
            }
          }
        }
      }

      // —— App pickers: what a slot opens, or an app for the dock.
      Item {
        id: appsView
        visible: root.view === "opens" || root.view === "dock-add"
        anchors.fill: parent

        SearchBox {
          id: appSearch
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          visible: appsView.visible
          query: root.filterText
          placeholder: "Search " + root.appCount + " apps"
          note: root.filterText ? (root.appCount === 1 ? "1 app" : root.appCount + " apps") : ""
        }

        ListView {
          id: appList
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: appSearch.bottom
          anchors.topMargin: root.gap
          anchors.bottom: parent.bottom
          clip: true
          spacing: root.listSpacing
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.appCount + 1

          delegate: SheetRow {
            required property int index
            readonly property var app: index === 0 ? null : (root.appRows[index - 1] || null)
            width: ListView.view.width - Style.space(8)
            height: root.appRowHeight
            rowIndex: index
            selected: root.selectedIndex === index
            glyph: index === 0 ? root.glyphGlobe : root.glyphWidget
            image: app && root.desktopApps ? String(root.desktopApps.iconSource(app.iconName) || "") : ""
            title: index === 0 ? "New web app" : String((app && app.name) || "")
            caption: index === 0 ? "Any site, opened in its own window" : String((app && app.detail) || "")
            checked: root.view === "opens" && !!app && root.activeTile.empty !== true
                     && TileModel.normalizeDesktopId(app.appId) === String(root.activeTile.desktop || "")
            chevron: index === 0
            onActivated: root.activateApp(index)
          }
        }

        ScrollHint { flick: appList }
        EdgeFade { flick: appList; atTop: true }
        EdgeFade { flick: appList; atTop: false }
      }

      // —— The icon dock: add, reorder, remove.
      ListView {
        id: dockListView
        visible: root.view === "dock"
        anchors.fill: parent
        clip: true
        spacing: root.listSpacing
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        model: root.dockNavCount

        delegate: SheetRow {
          id: dockRow
          required property int index
          readonly property bool isAdd: index === 0
          readonly property var item: isAdd ? null : (root.resolvedDock[index - 1] || { empty: true })
          width: ListView.view.width - Style.space(8)
          rowIndex: index
          selected: root.selectedIndex === index
          glyph: isAdd ? root.glyphPlus : String((item && item.icon) || root.glyphWidget)
          image: isAdd ? "" : root.launchImage(item)
          title: isAdd ? "Add an app" : root.dockLabel(item)
          caption: isAdd ? "An installed app or a web app"
                 : (index <= root.dockHintLetters.length ? "Space, then " + root.dockHintLetters[index - 1] : "No Space shortcut")
          chevron: isAdd
          onActivated: {
            root.selectedIndex = index
            if (isAdd) root.go("dock-add", 0)
          }

          IconAction {
            shown: !dockRow.isAdd
            dimmed: dockRow.index <= 1
            glyph: root.glyphUp
            onTriggered: root.moveDock(dockRow.index - 1, -1)
          }
          IconAction {
            shown: !dockRow.isAdd
            dimmed: dockRow.index >= root.dockCount
            glyph: root.glyphDown
            onTriggered: root.moveDock(dockRow.index - 1, 1)
          }
          IconAction {
            shown: !dockRow.isAdd
            danger: true
            glyph: root.glyphRemove
            onTriggered: root.removeDockAt(dockRow.index - 1)
          }
        }
      }

      ScrollHint { flick: dockListView; visible: needed && dockListView.visible }

      // —— A web app to open, or to add to the dock.
      Column {
        id: webForm
        visible: root.view === "webapp"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.md

        Text {
          width: parent.width
          bottomPadding: Style.space(6)
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.panelReturn === "dock"
                ? "Installs the site as a web app, the way Omarchy does, and puts it on the dock."
                : "Installs the site as a web app, the way Omarchy does. A click on the tile opens it; the widget does not change."
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          text: "Name"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        TextField {
          id: nameField
          width: parent.width
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          foreground: root.foreground
          placeholderText: "YouTube"
          text: root.webName
          onTextChanged: root.webName = text
          onAccepted: urlField.forceActiveFocus()
        }

        Text {
          topPadding: Style.space(4)
          textFormat: Text.PlainText
          text: "Address"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        TextField {
          id: urlField
          width: parent.width
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          foreground: root.foreground
          placeholderText: "https://youtube.com"
          text: root.webUrl
          onTextChanged: root.webUrl = text
          onAccepted: root.createWebApp()
        }

        Item { width: 1; height: Style.space(4) }

        Button {
          text: root.panelReturn === "dock" ? "Add to dock" : "Use this site"
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
        anchors.top: parent.top
        width: item && item.implicitWidth > 0 ? item.implicitWidth : parent.width
        height: item && item.implicitHeight > 0 ? item.implicitHeight : parent.height
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
}
