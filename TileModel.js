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

function resolveOne(tile, apps, catalog) {
  if (isEmptyTile(tile)) {
    return {
      empty: true, widget: "", widgetName: "Icon & link", label: "", icon: "", iconName: "",
      desktop: "", command: "", url: "", faviconUrl: "", faviconFallbackUrl: "",
      execString: "", hasLaunch: false
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

  if (app) {
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
    widgetName: meta ? String(meta.name || "Icon & link") : (widget ? widget : "Icon & link"),
    widgetQml: meta && meta.qml ? String(meta.qml) : "",
    label: label,
    icon: glyph,
    iconName: iconName,
    desktop: desktop,
    command: command,
    url: url,
    faviconUrl: (!iconName && url) ? faviconUrl(url) : "",
    faviconFallbackUrl: (!iconName && url) ? faviconFallbackUrl(url) : "",
    execString: execString,
    hasLaunch: !!(desktop || command || url)
  }
}

function resolveAll(tiles, slotCount, apps, catalog) {
  var source = Array.isArray(tiles) ? tiles : []
  var count = Math.max(0, slotCount)
  var out = []
  for (var i = 0; i < count; i++) out.push(resolveOne(source[i], apps, catalog))
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
  return out
}

function applyWidget(existing, widget) {
  var tile = existing && typeof existing === "object" ? storedTile(existing) || {} : {}
  if (!widget || !widget.id) {
    delete tile.widget
    // Drop widget chrome so icon-and-link can show the launch target's icon.
    delete tile.icon
    return isEmptyTile(tile) ? null : storedTile(tile)
  }
  tile.widget = String(widget.id)
  if ((widget.defaultLabel || widget.name) && (!tile.label || !hasLaunch(existing)))
    tile.label = String(widget.defaultLabel || widget.name)
  if (!hasLaunch(tile)) {
    if (widget.defaultUrl) tile.url = String(widget.defaultUrl)
    if (widget.defaultDesktop) tile.desktop = normalizeDesktopId(widget.defaultDesktop)
    if (widget.defaultCommand) tile.command = String(widget.defaultCommand)
  }
  return storedTile(tile)
}

function applyLaunch(existing, launch) {
  var tile = existing && typeof existing === "object" ? storedTile(existing) || {} : {}
  if (!launch) {
    delete tile.desktop
    delete tile.command
    delete tile.url
    delete tile.iconName
    return isEmptyTile(tile) ? null : storedTile(tile)
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
    faviconUrl: faviconUrl,
    faviconFallbackUrl: faviconFallbackUrl,
    resolveOne: resolveOne,
    resolveAll: resolveAll,
    storedTile: storedTile,
    storedTiles: storedTiles,
    applyWidget: applyWidget,
    applyLaunch: applyLaunch,
    fromDesktopEntry: fromDesktopEntry,
    fromUrl: fromUrl,
    fromAppRow: fromAppRow
  }
}
