function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8).toLowerCase() === ".desktop") value = value.slice(0, -8)
  return value
}

function isEmptyTile(tile) {
  if (!tile || typeof tile !== "object") return true
  return !(tile.desktop || tile.command || tile.url || tile.label)
}

function findEntry(appLibrary, desktop, label) {
  if (!appLibrary || typeof appLibrary.sortedEntries !== "function") return null

  var rows = appLibrary.sortedEntries("")
  var want = normalizeDesktopId(desktop)
  var wantLower = want.toLowerCase()
  var labelLower = String(label || "").toLowerCase()
  var byName = null

  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i] && rows[i].entry
    if (!entry) continue
    var id = normalizeDesktopId(entry.id)
    if (want && id === want) return entry
    if (want && id.toLowerCase() === wantLower) return entry
    if (!byName && labelLower && String(entry.name || "").toLowerCase() === labelLower)
      byName = entry
  }

  return byName
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

function resolveOne(tile, appLibrary) {
  if (isEmptyTile(tile)) {
    return { empty: true, type: "empty", label: "", icon: "", iconName: "", desktop: "", command: "", url: "", faviconUrl: "", faviconFallbackUrl: "", execString: "", entry: null }
  }

  var desktop = normalizeDesktopId(tile.desktop)
  var label = String(tile.label || "")
  var command = String(tile.command || "")
  var url = String(tile.url || "")
  var icon = String(tile.icon || "")
  var iconName = String(tile.iconName || "")
  var entry = findEntry(appLibrary, desktop, label)
  var execString = ""

  if (entry) {
    desktop = normalizeDesktopId(entry.id) || desktop
    if (!label && appLibrary && typeof appLibrary.entryName === "function")
      label = appLibrary.entryName(entry)
    if (!label) label = String(entry.name || "")
    if (!iconName) iconName = String(entry.icon || "")
    execString = String(entry.execString || "")
    if (!url) url = urlFromExec(execString)
  }

  if (!label) label = desktop || url || command
  if (!iconName && desktop) iconName = desktop.toLowerCase()

  return {
    empty: false,
    type: String(tile.type || "app"),
    label: label,
    icon: icon,
    iconName: iconName,
    desktop: desktop,
    command: command,
    url: url,
    faviconUrl: faviconUrl(url),
    faviconFallbackUrl: faviconFallbackUrl(url),
    execString: execString,
    entry: entry
  }
}

function resolveAll(tiles, slotCount, appLibrary) {
  var source = Array.isArray(tiles) ? tiles : []
  var count = Math.max(0, slotCount)
  var out = []
  for (var i = 0; i < count; i++) out.push(resolveOne(source[i], appLibrary))
  return out
}

function storedTile(tile) {
  if (isEmptyTile(tile)) return null
  var out = { type: String(tile.type || "app") }
  if (tile.label) out.label = String(tile.label)
  if (tile.desktop) out.desktop = normalizeDesktopId(tile.desktop)
  if (tile.command) out.command = String(tile.command)
  if (tile.url) out.url = String(tile.url)
  if (tile.icon) out.icon = String(tile.icon)
  if (tile.iconName) out.iconName = String(tile.iconName)
  return out
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

function fromUrl(url) {
  var value = String(url || "").trim()
  if (!value) return null
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) value = "https://" + value
  var label = value.replace(/^https?:\/\//i, "").replace(/\/$/, "")
  return { type: "app", label: label, url: value }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId: normalizeDesktopId,
    isEmptyTile: isEmptyTile,
    findEntry: findEntry,
    urlFromExec: urlFromExec,
    hostFromUrl: hostFromUrl,
    faviconUrl: faviconUrl,
    faviconFallbackUrl: faviconFallbackUrl,
    resolveOne: resolveOne,
    resolveAll: resolveAll,
    storedTile: storedTile,
    storedTiles: storedTiles,
    fromDesktopEntry: fromDesktopEntry,
    fromUrl: fromUrl
  }
}
