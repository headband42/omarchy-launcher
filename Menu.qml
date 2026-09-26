import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "TileModel.js" as TileModel

// Forked from $OMARCHY_PATH/shell/plugins/menu/Menu.qml.
// The stock card stays on the left; a 2x4 app-tile grid sits to its right.
// Tiles hide for dmenu/input mode so omarchy-menu-select keep working.
// Refresh MenuModel.js / BarWidget.qml with scripts/sync-upstream.sh.

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  property bool tileSettingsOpen: false
  property bool tileHintMode: false
  onOpenedChanged: if (!opened) {
    deleteConfirmOpen = false
    deleteTarget = null
    root.tileSettingsOpen = false
    root.tileHintMode = false
  }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  property var defaultTileConfig: ({})
  property var userTileConfig: ({})
  property var widgetCatalog: []
  readonly property var effectiveTileConfig: {
    var cfg = { columns: 4, rows: 2, tiles: [], dock: [] }
    var sources = [root.defaultTileConfig, root.userTileConfig]
    for (var s = 0; s < sources.length; s++) {
      var src = sources[s]
      if (!src || typeof src !== "object") continue
      if (src.columns) cfg.columns = src.columns
      if (src.rows) cfg.rows = src.rows
      if (Array.isArray(src.tiles)) cfg.tiles = src.tiles
      if (Array.isArray(src.dock)) cfg.dock = src.dock
      if (src.widgetSettings && typeof src.widgetSettings === "object" && !Array.isArray(src.widgetSettings))
        cfg.widgetSettings = src.widgetSettings
    }
    return TileModel.normalizeConfig(cfg)
  }
  readonly property var widgetSettings: root.effectiveTileConfig.widgetSettings || null
  readonly property int tileColumns: Math.max(1, Number(root.effectiveTileConfig.columns) || 4)
  readonly property int tileRows: Math.max(1, Number(root.effectiveTileConfig.rows) || 2)
  readonly property var tileItems: Array.isArray(root.effectiveTileConfig.tiles) ? root.effectiveTileConfig.tiles : []
  readonly property var dockItems: Array.isArray(root.effectiveTileConfig.dock) ? root.effectiveTileConfig.dock : []
  readonly property int tileGap: Style.spacing.md
  readonly property int layoutGap: Style.spacing.panelGap
  // Gear + dock share one row under tile 5 (flush left of tile 5, same icon size).
  readonly property int settingsButtonSize: Style.space(56)
  readonly property int dockIconSize: root.settingsButtonSize
  // Settings no longer sits beside the grid, so do not reserve a side gutter.
  readonly property int tileBudgetWidth: Math.max(0, (panel.width > 0 ? panel.width : Screen.width) - Style.gapsOut * 2 - root.cardWidth - root.layoutGap)
  readonly property int tileSize: {
    var fromHeight = Math.floor((root.cardHeight - root.tileGap * (root.tileRows - 1)) / root.tileRows)
    var fromWidth = Math.floor((root.tileBudgetWidth - root.tileGap * (root.tileColumns - 1)) / root.tileColumns)
    return Math.max(0, Math.min(fromHeight, fromWidth))
  }
  readonly property bool showTiles: root.opened && !root.dmenuActive && root.tileSize >= Style.space(64) && !root.filterText
  // A settings page that sizes itself sits alone. The tile grid stays hidden
  // so those widgets are not drawn beside that window.
  readonly property bool tilesBesideSettings: root.tileSettingsOpen && tileSettings.fitPanel
  // Hide launcher chrome for every settings page (same as weather/MLB fitPanel).
  readonly property bool settingsHidesChrome: root.tileSettingsOpen
  readonly property int tileGridWidth: root.showTiles && !root.settingsHidesChrome ? root.tileColumns * root.tileSize + (root.tileColumns - 1) * root.tileGap : 0
  readonly property int tileGridHeight: root.showTiles && !root.settingsHidesChrome ? root.tileRows * root.tileSize + (root.tileRows - 1) * root.tileGap : 0
  // One row under the grid for settings + dock icons.
  readonly property int belowGridHeight: {
    if (!root.showTiles || root.settingsHidesChrome) return 0
    return root.layoutGap + root.settingsButtonSize
  }
  // Settings sizes to content (home lists + widget fitPanel pages).
  readonly property int layoutWidth: {
    if (root.tileSettingsOpen) {
      var fit = tileSettings.fittedWidth
      var want = Math.max(fit > 0 ? fit : tileSettings.preferredWidth, root.cardWidth)
      var maxW = (panel.width > 0 ? panel.width : Screen.width) - Style.gapsOut * 2
      return Math.min(want, maxW)
    }
    return root.cardWidth + (root.showTiles ? root.layoutGap + root.tileGridWidth : 0)
  }
  readonly property int layoutHeight: {
    if (root.tileSettingsOpen) {
      var fit = tileSettings.fittedHeight
      var want = Math.max(fit > 0 ? fit : tileSettings.preferredHeight, Style.space(120))
      var maxH = (panel.height > 0 ? panel.height : Screen.height) - Style.gapsOut * 2
      return Math.min(want, maxH)
    }
    return Math.max(root.cardHeight, root.tileGridHeight + root.belowGridHeight)
  }
  // Tile 5 is 1-based (Space hints). In a 4×2 grid that is index 4 → column 0.
  readonly property int settingsTileIndex: 4
  readonly property int settingsColumn: root.settingsTileIndex % Math.max(1, root.tileColumns)
  readonly property color tileHoverFill: Qt.rgba(
    root.background.r + (root.foreground.r - root.background.r) * 0.22,
    root.background.g + (root.foreground.g - root.background.g) * 0.22,
    root.background.b + (root.foreground.b - root.background.b) * 0.22,
    root.background.a > 0 ? root.background.a : 1
  )
  property int appCatalogRevision: 0

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    var rows = desktopApps.list("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var row = rows[j]
      var appId = String(row.appId || "")
      if (!appId) continue
      var subtext = String(row.detail || "")
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(row.iconName || ""),
        appId: appId,
        label: String(row.name || appId),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: subtext ? [subtext] : [],
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.tileHintMode = false
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      desktopApps.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function expandHome(value) {
    var home = Quickshell.env("HOME") || ""
    return String(value || "").replace(/\$HOME\b/g, home).replace(/~/g, home)
  }

  function launchTile(tile) {
    if (!tile || tile.empty) return
    var resolved = TileModel.resolveOne(tile, desktopApps, root.widgetCatalog, root.widgetSettings)
    if (resolved.empty) return
    var desktop = TileModel.normalizeDesktopId(resolved.desktop)
    var url = String(resolved.url || "")
    var command = root.expandHome(String(resolved.command || ""))
    var execString = String(resolved.execString || "")
    var label = String(resolved.label || desktop || url || command)
    applySerial = requestSerial
    opened = false
    filterText = ""
    try {
      if (resolved.entry && typeof resolved.entry.execute === "function") {
        resolved.entry.execute()
        return
      }
    } catch (e) { }
    if (execString) {
      root.runAction(execString)
      return
    }
    if (url) {
      root.runAction("omarchy-launch-webapp " + Util.shellQuote(url))
      return
    }
    if (command) {
      root.runAction(command)
      return
    }
    if (desktop && root.appLibrary) root.appLibrary.launch(desktop, label)
  }

  // Widget clicks that name a page, such as one MLB game on Gameday.
  // Only https MLB links: the tile builds them, and a bad payload must not launch anything else.
  function openWebUrl(url) {
    var value = String(url || "").trim()
    var mlb = value.indexOf("https://www.mlb.com/") === 0 || value.indexOf("https://mlb.com/") === 0
    if (!mlb || value.indexOf(" ") >= 0 || value.indexOf("\n") >= 0 || value.indexOf("\t") >= 0
        || value.indexOf("\"") >= 0 || value.indexOf("'") >= 0 || value.indexOf("\\") >= 0)
      return
    root.opened = false
    root.runAction("omarchy-launch-webapp " + Util.shellQuote(value))
  }

  function tileHintDigit(event) {
    if (!event) return 0
    if (event.text && event.text.length === 1 && event.text >= "1" && event.text <= "9")
      return event.text.charCodeAt(0) - 48
    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) return event.key - Qt.Key_0
    return 0
  }

  // Dock Space-hints: q w e r t y u i o p (first dock icon = q).
  readonly property var dockHintLetters: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]

  function tileHintLetter(event) {
    if (!event) return ""
    var ch = ""
    if (event.text && event.text.length === 1) ch = String(event.text).toLowerCase()
    else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
      ch = String.fromCharCode(97 + (event.key - Qt.Key_A))
    if (!ch) return ""
    if (ch === "s") return "s"
    for (var i = 0; i < root.dockHintLetters.length; i++) {
      if (root.dockHintLetters[i] === ch) return ch
    }
    return ""
  }

  function dockIndexForHintLetter(ch) {
    var want = String(ch || "").toLowerCase()
    for (var i = 0; i < root.dockHintLetters.length; i++) {
      if (root.dockHintLetters[i] === want) return i
    }
    return -1
  }

  function isPlainSpace(event) {
    if (!event) return false
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
    if (event.key === Qt.Key_Space || event.key === Qt.Key_nobreakspace) return true
    return event.text === " "
  }

  function tilesReadyForHints() {
    return root.opened && !root.dmenuActive && !root.tileSettingsOpen && !root.filterText && root.tileSize >= Style.space(64)
  }

  // Returns true when the event was consumed as tile / dock / settings hinting.
  function handleTileHintKey(event) {
    if (root.dmenuActive || root.tileSettingsOpen || root.deleteConfirmOpen) return false

    if (!root.tileHintMode && root.tilesReadyForHints() && root.isPlainSpace(event)) {
      root.tileHintMode = true
      return true
    }

    if (!root.tileHintMode) return false

    if (event.key === Qt.Key_Escape || root.isPlainSpace(event)) {
      root.tileHintMode = false
      return true
    }

    var hintDigit = root.tileHintDigit(event)
    if (hintDigit >= 1 && hintDigit <= tileGrid.slotCount) {
      var hinted = tileGrid.resolvedTiles[hintDigit - 1]
      root.tileHintMode = false
      if (hinted && !hinted.empty) root.launchTile(hinted)
      return true
    }

    var letter = root.tileHintLetter(event)
    if (letter === "s") {
      root.tileHintMode = false
      root.tileSettingsOpen = true
      Qt.callLater(function() { tileSettings.forceActiveFocus() })
      return true
    }
    if (letter) {
      var dockIndex = root.dockIndexForHintLetter(letter)
      var dockResolved = iconDock.resolvedItems || []
      root.tileHintMode = false
      if (dockIndex >= 0 && dockIndex < dockResolved.length) {
        var dockItem = dockResolved[dockIndex]
        if (dockItem && !dockItem.empty) root.launchTile(dockItem)
      }
      return true
    }

    root.tileHintMode = false
    return false
  }

  function saveTileConfig(tiles, widgetSettings, dock) {
    var cfg = {
      columns: root.tileColumns,
      rows: root.tileRows,
      tiles: tiles
    }
    var dockList = dock !== undefined && dock !== null ? dock : root.dockItems
    cfg.dock = TileModel.storedDock(dockList)
    var memory = TileModel.copyWidgetSettings(widgetSettings)
    if (memory) cfg.widgetSettings = memory
    root.userTileConfig = cfg
    userTilesFile.setText(JSON.stringify(cfg, null, 2) + "\n")
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    desktopApps.refreshIcons()
    root.appCatalogRevision += 1
    if (root.providersLoaded["apps"]) root.mergeAppRows()
    widgetScan.running = true

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  DesktopApps {
    id: desktopApps
    appLibrary: root.appLibrary
  }

  Connections {
    target: desktopApps
    function onChanged() {
      root.appCatalogRevision += 1
      if (root.providersLoaded["apps"]) root.mergeAppRows()
      desktopApps.refreshIcons()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  function parseTileConfig(raw) {
    try {
      var parsed = JSON.parse(MenuModel.stripJsonc(raw || "") || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  FileView {
    id: defaultTilesFile
    path: {
      var url = String(Qt.resolvedUrl("tiles.json") || "")
      return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
    }
    watchChanges: true
    printErrors: false
    onLoaded: root.defaultTileConfig = root.parseTileConfig(text())
    onLoadFailed: root.defaultTileConfig = ({})
    onFileChanged: reload()
  }

  FileView {
    id: userTilesFile
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/" + ((root.manifest && root.manifest.id) ? root.manifest.id : "ande.launcher") + ".json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.userTileConfig = root.parseTileConfig(text())
    onLoadFailed: root.userTileConfig = ({})
    onFileChanged: reload()
  }

  function fileFromUrl(url) {
    var value = (url && url.toString) ? url.toString() : String(url || "")
    if (value.indexOf("file://") === 0) {
      value = decodeURIComponent(value.slice(7))
      if (value.indexOf("localhost/") === 0) value = value.slice(9)
    }
    return value
  }

  function iconLinkWidget() {
    return {
      id: "",
      name: "Icon & link",
      description: "No widget. The tile is just the icon for the app or site it opens.",
      icon: "󰖟"
    }
  }

  function applyWidgetScan(raw, ok) {
    var rows = []
    if (ok) {
      try { rows = JSON.parse(raw || "[]") } catch (e) { rows = [] }
    }
    if (!Array.isArray(rows)) rows = []
    rows.unshift(root.iconLinkWidget())
    root.widgetCatalog = rows
  }

  Process {
    id: widgetScan
    command: [
      "/usr/bin/python3",
      root.fileFromUrl(Qt.resolvedUrl("scripts/list-widgets.py")),
      root.fileFromUrl(Qt.resolvedUrl("widgets")),
      Quickshell.env("HOME") + "/.config/omarchy/extensions/ande.launcher/widgets"
    ]
    stdout: StdioCollector {
      id: widgetScanOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      root.applyWidgetScan(widgetScanOut.text, exitCode === 0)
    }
  }

  Component.onCompleted: widgetScan.running = true

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.layoutHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1 }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Item {
      id: layout
      width: root.layoutWidth
      height: Math.min(root.layoutHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop

    BorderSurface {
      id: card
      visible: !root.tileSettingsOpen
      width: root.cardWidth
      height: Math.min(root.cardHeight, layout.height)
      radius: root.cornerRadius
      anchors.left: parent.left
      anchors.top: parent.top
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onShortcutOverride: function(event) {
          if (tileGrid.widgetEntryActive) return
          if (root.isPlainSpace(event) && (root.tilesReadyForHints() || root.tileHintMode))
            event.accepted = true
          else if (root.tileHintMode && (root.tileHintDigit(event) >= 1 || root.tileHintLetter(event)))
            event.accepted = true
        }
        Keys.onPressed: function(event) {
          if (tileGrid.widgetEntryActive) return
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (root.tileSettingsOpen) {
            if (tileSettings.handleKey(event)) event.accepted = true
            return
          }

          if (root.handleTileHintKey(event)) {
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.tileSettingsOpen && tileSettings.handleEscape()) {}
            else if (root.tileHintMode) root.tileHintMode = false
            else if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            if (!root.filterText && root.isPlainSpace(event) && root.tilesReadyForHints()) {
              root.tileHintMode = true
              event.accepted = true
              return
            }
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…"))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp ? desktopApps.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }

      TileGrid {
        id: tileGrid
        visible: root.showTiles && !root.settingsHidesChrome
        width: root.tileGridWidth
        height: root.tileGridHeight
        anchors.left: card.right
        anchors.leftMargin: root.showTiles ? root.layoutGap : 0
        anchors.top: card.top
        columns: root.tileColumns
        rows: root.tileRows
        tileSize: root.tileSize
        gap: root.tileGap
        tiles: root.tileItems
        appLibrary: root.appLibrary
        catalogRevision: root.appCatalogRevision
        widgetCatalog: root.widgetCatalog
        widgetSettings: root.widgetSettings
        desktopApps: desktopApps
        fontFamily: root.fontFamily
        foreground: root.foreground
        background: root.background
        hoverFill: root.tileHoverFill
        selectedText: root.selectedText
        idleBorderSpec: root.borderSpec
        selectedBorderSpec: root.selectedBorderSpec
        cornerRadius: root.cornerRadius
        hintMode: root.tileHintMode
        onActivated: function(tile) { root.launchTile(tile) }
        onOpenFolder: function(path) {
          root.openVolume(path, "")
        }
        onOpenUrl: function(url) { root.openWebUrl(url) }
        onOpenVolume: function(path, device) {
          root.opened = false
          var script = root.fileFromUrl(Qt.resolvedUrl("widgets/disks/open-volume.sh"))
          Util.execDetached("bash " + Util.shellQuote(script) + " " + Util.shellQuote(path || "") + " " + Util.shellQuote(device || ""))
        }
        onOpenTerminal: function(path) {
          if (!path) return
          root.opened = false
          Util.execDetached("uwsm-app -- xdg-terminal-exec --dir=" + Util.shellQuote(path))
        }
        onDismiss: root.cancel()
        onTypeText: function(text) {
          root.setFilter(root.filterText + text)
        }
      }

      BorderSurface {
        id: settingsButton
        visible: root.showTiles && !root.settingsHidesChrome
        width: root.settingsButtonSize
        height: root.settingsButtonSize
        // Flush with left edge of tile 5; dock icons continue to the right.
        x: tileGrid.x + root.settingsColumn * (root.tileSize + root.tileGap)
        y: tileGrid.y + root.tileGridHeight + root.layoutGap
        z: 4
        radius: root.cornerRadius
        color: settingsMouse.containsMouse ? root.tileHoverFill : root.background
        borderSpec: root.borderSpec

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: ""
          color: settingsMouse.containsMouse ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
          opacity: root.tileHintMode ? 0.35 : 1
        }

        MouseArea {
          id: settingsMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.tileHintMode = false
            root.tileSettingsOpen = true
            Qt.callLater(function() { tileSettings.forceActiveFocus() })
          }
        }

        Rectangle {
          visible: root.tileHintMode
          width: Math.round(Math.min(parent.width, parent.height) * 0.46)
          height: width
          radius: width / 2
          anchors.centerIn: parent
          color: root.tileHoverFill
          border.width: Math.max(1, Style.space(2))
          border.color: root.foreground
          z: 5

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "s"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Math.round(parent.width * 0.58)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      IconDock {
        id: iconDock
        visible: root.showTiles && !root.settingsHidesChrome && root.dockItems.length > 0
        x: settingsButton.x + settingsButton.width + root.tileGap
        y: settingsButton.y
        z: 3
        items: root.dockItems
        desktopApps: desktopApps
        catalogRevision: root.appCatalogRevision
        iconSize: root.dockIconSize
        gap: root.tileGap
        fontFamily: root.fontFamily
        foreground: root.foreground
        background: root.background
        hoverFill: root.tileHoverFill
        idleBorderSpec: root.borderSpec
        selectedBorderSpec: root.selectedBorderSpec
        cornerRadius: root.cornerRadius
        hintMode: root.tileHintMode
        onActivated: function(item) { root.launchTile(item) }
      }

      TileSettings {
        id: tileSettings
        visible: root.showTiles && root.tileSettingsOpen
        z: 8
        x: 0
        y: 0
        width: layout.width
        // Settings owns the stage while open — roomier than the launcher card.
        height: layout.height
        hostHeight: layout.height
        tiles: root.tileItems
        dock: root.dockItems
        appLibrary: root.appLibrary
        catalogRevision: root.appCatalogRevision
        widgetCatalog: root.widgetCatalog
        widgetSettings: root.widgetSettings
        desktopApps: desktopApps
        columns: root.tileColumns
        rows: root.tileRows
        fontFamily: root.fontFamily
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        hoverFill: root.tileHoverFill
        selectedText: root.selectedText
        borderSpec: root.borderSpec
        cornerRadius: root.cornerRadius
        onSaveTiles: function(tiles, widgetSettings) { root.saveTileConfig(tiles, widgetSettings) }
        onSaveDock: function(dock) { root.saveTileConfig(root.tileItems, root.widgetSettings, dock) }
        onClosed: {
          root.tileSettingsOpen = false
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }
    }
  }
}
