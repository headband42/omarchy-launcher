import QtQuick
import Quickshell
import "TileModel.js" as TileModel

// Single app catalog for this plugin. Same backing store as the stock
// AppLibrary (DesktopEntries + iconSource/launch on the shell), snapshotted
// to plain data so we never pass DesktopEntry QObjects through the
// third-party facade.
Item {
  id: root
  property var appLibrary: null

  signal changed()

  function list(query) {
    var fromLib = root.snapshotFromLibrary(query)
    if (fromLib.length) return fromLib
    return root.listFromDesktopEntries(query)
  }

  function snapshotFromLibrary(query) {
    if (!root.appLibrary || typeof root.appLibrary.sortedEntries !== "function") return []
    var rows = []
    try { rows = root.appLibrary.sortedEntries(query || "") || [] } catch (e) { return [] }
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var entry = row && (row.entry || row)
      var id = String((entry && entry.id) || (row && row.appId) || "")
      var name = ""
      if (entry && typeof root.appLibrary.entryName === "function")
        name = String(root.appLibrary.entryName(entry) || "")
      if (!name) name = String((entry && entry.name) || (row && row.name) || "")
      if (!id || !name) continue
      var detail = ""
      if (entry && typeof root.appLibrary.entrySubtext === "function")
        detail = String(root.appLibrary.entrySubtext(entry) || "")
      if (!detail) detail = String((entry && entry.genericName) || (row && row.detail) || "")
      out.push({
        appId: TileModel.normalizeDesktopId(id),
        name: name,
        detail: detail,
        iconName: String((entry && entry.icon) || (row && row.iconName) || ""),
        url: TileModel.urlFromExec(String((entry && entry.execString) || "")),
        execString: String((entry && entry.execString) || "")
      })
    }
    return out
  }

  function listFromDesktopEntries(query) {
    var q = String(query || "").trim().toLowerCase()
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { values = [] }
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var id = String(entry.id || "")
      var name = String(entry.name || "")
      if (!id || !name) continue
      var detail = String(entry.genericName || "")
      var hay = (name + " " + id + " " + detail).toLowerCase()
      if (q && hay.indexOf(q) < 0) continue
      out.push({
        appId: TileModel.normalizeDesktopId(id),
        name: name,
        detail: detail,
        iconName: String(entry.icon || ""),
        url: TileModel.urlFromExec(String(entry.execString || "")),
        execString: String(entry.execString || "")
      })
    }
    out.sort(function(a, b) {
      var an = String(a.name || "").toLowerCase()
      var bn = String(b.name || "").toLowerCase()
      if (an < bn) return -1
      if (an > bn) return 1
      return 0
    })
    return out
  }

  function find(desktop, label) {
    var want = TileModel.normalizeDesktopId(desktop)
    var wantLower = want.toLowerCase()
    var labelLower = String(label || "").toLowerCase()
    var rows = root.list("")
    var byName = null
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var id = TileModel.normalizeDesktopId(row.appId)
      if (want && id === want) return row
      if (want && id.toLowerCase() === wantLower) return row
      if (!byName && labelLower && String(row.name || "").toLowerCase() === labelLower) byName = row
    }
    return byName
  }

  function iconSource(name) {
    var value = String(name || "")
    if (!value) return ""
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function") {
      var fromLib = String(root.appLibrary.iconSource(value) || "")
      if (fromLib) return fromLib
    }
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var themed = Quickshell.iconPath(value, true)
    if (themed) return themed
    return ""
  }

  function launch(desktopId, name) {
    if (root.appLibrary && typeof root.appLibrary.launch === "function")
      root.appLibrary.launch(desktopId, name)
  }

  function refreshIcons() {
    if (root.appLibrary && typeof root.appLibrary.refreshIcons === "function")
      root.appLibrary.refreshIcons()
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.changed() }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.changed() }
  }
}
