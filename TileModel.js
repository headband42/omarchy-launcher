function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8).toLowerCase() === ".desktop") value = value.slice(0, -8)
  return value
}

function widgetId(tile) {
  return String((tile && tile.widget) || "")
}

function hasLaunch(tile) {
  return !!(tile && (tile.desktop || tile.command || tile.url))
}

function isEmptyTile(tile) {
  if (!tile || typeof tile !== "object") return true
  return !widgetId(tile) && !hasLaunch(tile) && !tile.label && !tile.icon
}

// Slot settings belong to one widget instance. Drop anything that is not a
// plain JSON object so a bad edit cannot persist functions or arrays here.
function copySettings(settings) {
  if (!settings || typeof settings !== "object" || Array.isArray(settings)) return null
  var cloned
  try { cloned = JSON.parse(JSON.stringify(settings)) } catch (e) { return null }
  if (!cloned || typeof cloned !== "object" || Array.isArray(cloned)) return null
  var keys = Object.keys(cloned)
  if (keys.length === 0) return null
  return cloned
}

// Remembered per widget id so removing a widget and adding it back restores
// its panel. Active settings still live on `settings` for the current widget.
function copyWidgetSettings(memory) {
  if (!memory || typeof memory !== "object" || Array.isArray(memory)) return null
  var cloned
  try { cloned = JSON.parse(JSON.stringify(memory)) } catch (e) { return null }
  if (!cloned || typeof cloned !== "object" || Array.isArray(cloned)) return null
  var out = {}
  var keys = Object.keys(cloned)
  for (var i = 0; i < keys.length; i++) {
    var id = String(keys[i] || "")
    if (!id) continue
    var settings = copySettings(cloned[id])
    if (settings) out[id] = settings
  }
  return Object.keys(out).length > 0 ? out : null
}

// What the picker calls a slot with no widget: just the icon for what it opens.
var ICON_LINK_NAME = "Icon & link"

function iconLinkWidget() {
  return {
    id: "",
    name: ICON_LINK_NAME,
    description: "No widget. The tile is just the icon for the app or site it opens.",
    icon: "󰖟"
  }
}

// The scanned widgets with Icon & link first, unless it is already there.
function withIconLink(catalog) {
  var list = Array.isArray(catalog) ? catalog.slice() : []
  for (var i = 0; i < list.length; i++) {
    if (!String(list[i].id || "")) return list
  }
  list.unshift(iconLinkWidget())
  return list
}

// The widget picker's sections, in this order. A widget names its own in
// widget.json `category`. One that names another category is grouped after
// these under that name; one that names none goes under Other, last.
var WIDGET_CATEGORIES = ["Everyday", "System", "Developer", "AI plans", "News & markets", "Sports", "Media"]
var OTHER_CATEGORY = "Other"

// Icon & link has no category and sits above every section.
function widgetCategory(widget) {
  if (!widget || !String(widget.id || "")) return ""
  return String(widget.category || "").trim() || OTHER_CATEGORY
}

function categoryRank(name) {
  if (!name) return -1
  var known = WIDGET_CATEGORIES.indexOf(name)
  if (known >= 0) return known
  return name === OTHER_CATEGORY ? WIDGET_CATEGORIES.length + 1 : WIDGET_CATEGORIES.length
}

function compareText(a, b) {
  var x = String(a || "").toLowerCase()
  var y = String(b || "").toLowerCase()
  return x < y ? -1 : (x > y ? 1 : 0)
}

function compareWidgets(a, b) {
  return compareText(a.name || a.id, b.name || b.id) || compareText(a.id, b.id)
}

// How well a widget answers a search, lower is better and -1 is no match.
// Every word has to be found, and a word found in the name counts for more
// than one found in the category or the description.
function widgetMatch(widget, query) {
  var words = String(query || "").toLowerCase().split(/\s+/).filter(function(w) { return w.length > 0 })
  if (!widget || words.length === 0) return 0
  var name = String(widget.name || "").toLowerCase()
  var id = String(widget.id || "").toLowerCase()
  var category = widgetCategory(widget).toLowerCase()
  var description = String(widget.description || "").toLowerCase()
  var total = 0
  for (var i = 0; i < words.length; i++) {
    var word = words[i]
    if (name.indexOf(word) === 0 || id.indexOf(word) === 0) total += 0
    else if ((" " + name).indexOf(" " + word) >= 0) total += 1
    else if (name.indexOf(word) >= 0 || id.indexOf(word) >= 0) total += 2
    else if (category.indexOf(word) >= 0) total += 3
    else if (description.indexOf(word) >= 0) total += 4
    else return -1
  }
  return total
}

// Rows for the widget picker. With no search: Icon & link, then each section
// under a header row, names in order. With a search: the matches, best first,
// with no headers. A widget row carries `pick`, its place among the rows that
// can be chosen, so the keyboard can step over the headers.
function pickerRows(catalog, query) {
  var list = withIconLink(catalog)
  var rows = []
  var picks = 0
  var i
  if (String(query || "").trim()) {
    var hits = []
    for (i = 0; i < list.length; i++) {
      var score = widgetMatch(list[i], query)
      if (score >= 0) hits.push({ widget: list[i], score: score })
    }
    hits.sort(function(a, b) { return (a.score - b.score) || compareWidgets(a.widget, b.widget) })
    for (i = 0; i < hits.length; i++) rows.push({ kind: "widget", widget: hits[i].widget, pick: picks++ })
    return rows
  }
  var groups = {}
  var names = []
  for (i = 0; i < list.length; i++) {
    var category = widgetCategory(list[i])
    if (!groups.hasOwnProperty(category)) {
      groups[category] = []
      names.push(category)
    }
    groups[category].push(list[i])
  }
  names.sort(function(a, b) { return (categoryRank(a) - categoryRank(b)) || compareText(a, b) })
  for (var n = 0; n < names.length; n++) {
    var members = groups[names[n]].slice().sort(compareWidgets)
    if (names[n]) rows.push({ kind: "header", title: names[n] })
    for (var m = 0; m < members.length; m++) rows.push({ kind: "widget", widget: members[m], pick: picks++ })
  }
  return rows
}

// The pick index of a widget id in pickerRows output, or 0.
function pickOf(rows, id) {
  var want = String(id || "")
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].kind === "widget" && String(list[i].widget.id || "") === want) return list[i].pick
  }
  return 0
}

// Arrow keys on the settings home. The slots are the grid they are on screen,
// numbered in reading order, and the icon dock is one more row under them at
// index columns * rows. Left and right step through the numbers; up and down
// keep the column and pass through the dock. `column` is where to land when
// leaving the dock.
function homeMove(index, dx, dy, columns, rows, column) {
  var cols = Math.max(1, Math.floor(Number(columns) || 1))
  var lines = Math.max(1, Math.floor(Number(rows) || 1))
  var count = cols * lines
  var dock = count
  var at = Math.floor(Number(index) || 0)
  if (at < 0 || at > dock) at = 0
  if (dx) return at === dock ? dock : ((at + dx) % count + count) % count
  if (!dy) return at
  var col = at === dock ? Math.min(Math.max(0, Math.floor(Number(column) || 0)), cols - 1) : at % cols
  var line = at === dock ? (dy > 0 ? -1 : lines) : Math.floor(at / cols)
  line += dy > 0 ? 1 : -1
  if (line < 0 || line >= lines) return dock
  return line * cols + col
}

function findWidget(catalog, id) {
  var want = String(id || "")
  var list = Array.isArray(catalog) ? catalog : []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id || "") === want) return list[i]
  }
  return null
}

function lookupApp(apps, desktop, label) {
  if (!apps || typeof apps.find !== "function") return null
  return apps.find(desktop, label)
}

function urlFromExec(execString) {
  var value = String(execString || "")
  var match = value.match(/omarchy-launch-webapp\s+(?:--\s+)?["']?(\S+)/)
  if (!match) return ""
  return match[1].replace(/["']$/, "")
}

function hostFromUrl(url) {
  var value = String(url || "").trim()
  var match = value.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/?#:]+)/)
  if (!match) return ""
  return match[1].toLowerCase().replace(/^www\./, "")
}

// A web link a widget asks to open in the default browser (a feed headline, a
// pull request, a meeting). http or https only, no whitespace, quotes, angle
// brackets, or backslashes, and a real host. Anything else comes back "".
function linkTarget(url) {
  var value = String(url || "").trim()
  if (value.length > 2048) return ""
  if (!/^https?:\/\/[^\s"'<>\\`]+$/.test(value)) return ""
  if (/[\x00-\x1f\x7f]/.test(value)) return ""
  return hostFromUrl(value) ? value : ""
}

function faviconUrl(url) {
  var host = hostFromUrl(url)
  if (!host) return ""
  return "https://www.google.com/s2/favicons?sz=128&domain_url=" + encodeURIComponent("https://" + host)
}

function faviconFallbackUrl(url) {
  var host = hostFromUrl(url)
  if (!host) return ""
  return "https://icons.duckduckgo.com/ip3/" + encodeURIComponent(host) + ".ico"
}

function resolveSettings(tile, memory) {
  var widget = widgetId(tile)
  if (!widget) return {}
  // A remembered map belongs to the widget. Every slot using that widget
  // shows the same settings, including one it was just moved onto.
  if (memory && typeof memory === "object" && !Array.isArray(memory))
    return copySettings(memory[widget]) || {}
  return copySettings(tile && tile.settings) || {}
}

function resolveOne(tile, apps, catalog, memory) {
  if (isEmptyTile(tile)) {
    return {
      empty: true, widget: "", widgetName: ICON_LINK_NAME, label: "", appName: "", icon: "", iconName: "",
      desktop: "", command: "", url: "", faviconUrl: "", faviconFallbackUrl: "",
      execString: "", hasLaunch: false, settings: {}, settingsQml: ""
    }
  }

  var widget = widgetId(tile)
  var meta = findWidget(catalog, widget)
  var desktop = normalizeDesktopId(tile.desktop)
  var label = String(tile.label || "")
  var command = String(tile.command || "")
  var url = String(tile.url || "")
  var app = lookupApp(apps, desktop, label)
  var execString = ""
  var iconName = String(tile.iconName || "")
  var appName = ""

  if (app) {
    appName = String(app.name || "")
    desktop = normalizeDesktopId(app.appId) || desktop
    if (!iconName) iconName = String(app.iconName || "")
    execString = String(app.execString || "")
    if (!url) url = String(app.url || "")
    if (!widget && !label) label = String(app.name || "")
  }

  if (!label) label = (meta && (meta.defaultLabel || meta.name)) || desktop || url || command

  // Widget glyphs live in Widget.qml, not on the launch target. A leftover
  // nerd-font `icon` from a previous widget must not replace the app icon.
  var glyph = widget ? "" : String(tile.icon || "")
  if (iconName) glyph = ""

  return {
    empty: false,
    widget: widget,
    widgetName: meta ? String(meta.name || ICON_LINK_NAME) : (widget ? widget : ICON_LINK_NAME),
    widgetQml: meta && meta.qml ? String(meta.qml) : "",
    label: label,
    appName: appName,
    icon: glyph,
    iconName: iconName,
    desktop: desktop,
    command: command,
    url: url,
    faviconUrl: (!iconName && url) ? faviconUrl(url) : "",
    faviconFallbackUrl: (!iconName && url) ? faviconFallbackUrl(url) : "",
    execString: execString,
    hasLaunch: !!(desktop || command || url),
    settings: resolveSettings(tile, memory),
    settingsQml: meta && meta.settingsQml ? String(meta.settingsQml) : ""
  }
}

// What a slot opens, in a few words. A slot with no widget keeps the name of
// what it opens as its label. A widget slot's label is the widget's, so it
// names the app, the site's host, or the command without the wrappers
// Omarchy puts in front of a program.
function launchLabel(tile) {
  if (!tile || !hasLaunch(tile)) return ""
  if (!widgetId(tile) && tile.label) return String(tile.label)
  if (tile.desktop) return String(tile.appName || normalizeDesktopId(tile.desktop))
  if (tile.url) return hostFromUrl(tile.url) || String(tile.url)
  return String(tile.command || "").trim()
    .replace(/^uwsm-app\s+--\s+/, "")
    .replace(/^xdg-terminal-exec\s+/, "")
    .replace(/^omarchy-launch-tui\s+/, "")
    .replace(/^omarchy-launch-/, "")
}

function resolveAll(tiles, slotCount, apps, catalog, memory) {
  var source = Array.isArray(tiles) ? tiles : []
  var count = Math.max(0, slotCount)
  var out = []
  for (var i = 0; i < count; i++) out.push(resolveOne(source[i], apps, catalog, memory))
  return out
}

function storedTile(tile) {
  if (isEmptyTile(tile)) return null
  var out = {}
  var widget = widgetId(tile)
  if (widget) out.widget = widget
  if (tile.label) out.label = String(tile.label)
  if (tile.desktop) out.desktop = normalizeDesktopId(tile.desktop)
  if (tile.command) out.command = String(tile.command)
  if (tile.url) out.url = String(tile.url)
  if (tile.icon) out.icon = String(tile.icon)
  if (tile.iconName) out.iconName = String(tile.iconName)
  // Settings shown on this slot. The copy that survives a move lives in the
  // config's widgetSettings map, not on the slot.
  if (widget) {
    var settings = copySettings(tile.settings)
    if (settings) out.settings = settings
  }
  return out
}

function rememberWidget(memory, id, settings) {
  var next = copyWidgetSettings(memory) || {}
  var widget = String(id || "")
  if (!widget) return Object.keys(next).length > 0 ? next : null
  var copied = copySettings(settings)
  if (copied) next[widget] = copied
  else delete next[widget]
  return Object.keys(next).length > 0 ? next : null
}

// Pull settings that were saved on a slot up into the widget map, then stamp
// every current copy of that widget with the same settings.
function normalizeConfig(config) {
  var source = config && typeof config === "object" ? config : {}
  var global = copyWidgetSettings(source.widgetSettings) || {}
  var memory = copyWidgetSettings(global) || {}
  var tiles = Array.isArray(source.tiles) ? source.tiles : []
  var i
  for (i = 0; i < tiles.length; i++) {
    var tile = tiles[i]
    if (!tile || typeof tile !== "object") continue
    var slotMemory = copyWidgetSettings(tile.widgetSettings)
    var id = widgetId(tile)
    var current = id ? copySettings(tile.settings) : null
    if (slotMemory) {
      var ids = Object.keys(slotMemory)
      for (var j = 0; j < ids.length; j++) {
        if (!memory[ids[j]]) memory[ids[j]] = slotMemory[ids[j]]
      }
    }
    if (id && current && !global[id]) memory[id] = current
  }
  var out = []
  for (i = 0; i < tiles.length; i++) {
    var stored = storedTile(tiles[i])
    if (stored) {
      var storedId = widgetId(stored)
      if (storedId && memory[storedId]) stored.settings = copySettings(memory[storedId])
      else if (storedId) delete stored.settings
    }
    out.push(stored)
  }
  return {
    columns: source.columns,
    rows: source.rows,
    tiles: out,
    dock: storedDock(source.dock),
    widgetSettings: Object.keys(memory).length > 0 ? memory : null
  }
}

function applySettingsToTiles(tiles, slotCount, id, settings) {
  var want = String(id || "")
  var source = storedTiles(tiles, slotCount)
  for (var i = 0; i < source.length; i++) {
    if (!source[i] || widgetId(source[i]) !== want) continue
    source[i] = applySettings(source[i], settings)
  }
  return source
}

// Default save for every settings panel. The object is stored under the
// widget id, then copied onto each slot that currently shows that widget.
// Null or an empty object forgets it. A second save of the same object
// reports changed: false so the panel can ignore its own echo.
function saveWidgetSettings(tiles, slotCount, memory, widgetId, settings) {
  var id = String(widgetId || "")
  var beforeTiles = storedTiles(tiles, slotCount)
  var beforeMemory = copyWidgetSettings(memory) || null
  if (!id) return { tiles: beforeTiles, widgetSettings: beforeMemory, changed: false }
  var nextMemory = rememberWidget(beforeMemory, id, settings)
  var nextTiles = applySettingsToTiles(beforeTiles, slotCount, id, settings)
  var changed = JSON.stringify(beforeMemory) !== JSON.stringify(nextMemory)
    || JSON.stringify(beforeTiles) !== JSON.stringify(nextTiles)
  return { tiles: nextTiles, widgetSettings: nextMemory, changed: changed }
}

function applyWidget(existing, widget, memory) {
  var previous = widgetId(existing)
  var tile = existing && typeof existing === "object" ? storedTile(existing) || {} : {}
  var nextId = widget && widget.id ? String(widget.id) : ""
  if (!nextId) {
    delete tile.widget
    delete tile.settings
    // Drop widget chrome so icon-and-link can show the launch target's icon.
    delete tile.icon
    return storedTile(tile)
  }
  // A different widget must not inherit the previous one's settings.
  // Settings for the widget being added come from the widget map.
  if (nextId !== previous) delete tile.settings
  var restored = copySettings(memory && memory[nextId])
  if (restored) tile.settings = restored
  tile.widget = nextId
  if ((widget.defaultLabel || widget.name) && (!tile.label || !hasLaunch(existing)))
    tile.label = String(widget.defaultLabel || widget.name)
  // Changing widget type resets Opens to that widget's default launch target.
  // Do not keep the previous widget's desktop/command/url (or a leftover
  // themed iconName). Widget-specific panel settings still come from the
  // shared widgetSettings map above — only the linked app is overridden.
  if (previous && nextId !== previous) {
    delete tile.desktop
    delete tile.command
    delete tile.url
    delete tile.iconName
  }
  if (!hasLaunch(tile)) {
    if (widget.defaultUrl) tile.url = String(widget.defaultUrl)
    if (widget.defaultDesktop) tile.desktop = normalizeDesktopId(widget.defaultDesktop)
    if (widget.defaultCommand) tile.command = String(widget.defaultCommand)
  }
  return storedTile(tile)
}

function applySettings(existing, settings) {
  var tile = existing && typeof existing === "object" ? storedTile(existing) || {} : {}
  if (!widgetId(tile)) return isEmptyTile(tile) ? null : storedTile(tile)
  var copied = copySettings(settings)
  if (copied) tile.settings = copied
  else delete tile.settings
  return storedTile(tile)
}

function applyLaunch(existing, launch) {
  var tile = existing && typeof existing === "object" ? storedTile(existing) || {} : {}
  if (!launch) {
    delete tile.desktop
    delete tile.command
    delete tile.url
    delete tile.iconName
    return storedTile(tile)
  }
  if (launch.desktop) tile.desktop = normalizeDesktopId(launch.desktop)
  else delete tile.desktop
  if (launch.command) tile.command = String(launch.command)
  else delete tile.command
  if (launch.url) tile.url = String(launch.url)
  else delete tile.url
  if (launch.iconName) tile.iconName = String(launch.iconName)
  else delete tile.iconName
  // Launch targets use themed desktop icons. Do not keep a widget glyph.
  delete tile.icon
  if (!widgetId(tile) && launch.label) tile.label = String(launch.label)
  return storedTile(tile)
}

function storedTiles(tiles, slotCount) {
  var source = Array.isArray(tiles) ? tiles : []
  var count = Math.max(0, slotCount)
  var out = []
  for (var i = 0; i < count; i++) out.push(storedTile(source[i]))
  return out
}

function fromDesktopEntry(entry, appLibrary) {
  if (!entry) return null
  var label = ""
  if (appLibrary && typeof appLibrary.entryName === "function") label = appLibrary.entryName(entry)
  if (!label) label = String(entry.name || "")
  return {
    type: "app",
    desktop: normalizeDesktopId(entry.id),
    label: label,
    iconName: String(entry.icon || ""),
    url: urlFromExec(entry.execString || "")
  }
}

function fromUrl(url, name) {
  var value = String(url || "").trim()
  if (!value) return null
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) value = "https://" + value
  var label = String(name || "").trim()
  if (!label) label = value.replace(/^https?:\/\//i, "").replace(/\/$/, "")
  return { type: "app", label: label, url: value }
}

function fromAppRow(row) {
  if (!row) return null
  return {
    desktop: normalizeDesktopId(row.appId),
    label: String(row.name || ""),
    iconName: String(row.iconName || ""),
    url: String(row.url || "")
  }
}


function storedDockItem(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return null
  var out = {}
  if (item.label) out.label = String(item.label)
  if (item.desktop) out.desktop = normalizeDesktopId(item.desktop)
  if (item.command) out.command = String(item.command)
  if (item.url) out.url = String(item.url)
  if (item.iconName) out.iconName = String(item.iconName)
  // Dock is icon-only launchers. Keep a nerd-font glyph only when there is
  // no desktop icon name to resolve.
  if (item.icon && !out.iconName) out.icon = String(item.icon)
  if (!out.desktop && !out.command && !out.url) return null
  return out
}

function storedDock(items) {
  var source = Array.isArray(items) ? items : []
  var out = []
  for (var i = 0; i < source.length; i++) {
    var item = storedDockItem(source[i])
    if (item) out.push(item)
  }
  return out
}

function resolveDock(items, apps) {
  var source = storedDock(items)
  var out = []
  for (var i = 0; i < source.length; i++) out.push(resolveOne(source[i], apps, [], null))
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId: normalizeDesktopId,
    widgetId: widgetId,
    hasLaunch: hasLaunch,
    isEmptyTile: isEmptyTile,
    findWidget: findWidget,
    lookupApp: lookupApp,
    urlFromExec: urlFromExec,
    hostFromUrl: hostFromUrl,
    linkTarget: linkTarget,
    faviconUrl: faviconUrl,
    faviconFallbackUrl: faviconFallbackUrl,
    resolveOne: resolveOne,
    resolveAll: resolveAll,
    launchLabel: launchLabel,
    storedTile: storedTile,
    storedTiles: storedTiles,
    ICON_LINK_NAME: ICON_LINK_NAME,
    iconLinkWidget: iconLinkWidget,
    withIconLink: withIconLink,
    WIDGET_CATEGORIES: WIDGET_CATEGORIES,
    OTHER_CATEGORY: OTHER_CATEGORY,
    widgetCategory: widgetCategory,
    widgetMatch: widgetMatch,
    pickerRows: pickerRows,
    pickOf: pickOf,
    homeMove: homeMove,
    copySettings: copySettings,
    copyWidgetSettings: copyWidgetSettings,
    rememberWidget: rememberWidget,
    normalizeConfig: normalizeConfig,
    resolveSettings: resolveSettings,
    applyWidget: applyWidget,
    applySettings: applySettings,
    applySettingsToTiles: applySettingsToTiles,
    saveWidgetSettings: saveWidgetSettings,
    applyLaunch: applyLaunch,
    fromDesktopEntry: fromDesktopEntry,
    fromUrl: fromUrl,
    fromAppRow: fromAppRow,
    storedDockItem: storedDockItem,
    storedDock: storedDock,
    resolveDock: resolveDock
  }
}
