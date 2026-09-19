import QtQuick
import Quickshell
import "TileModel.js" as TileModel

// One catalog of installed desktop entries for this plugin.
// The stock menu reads DesktopEntries through AppLibrary. Third-party
// plugins only get a JS facade; QObject DesktopEntry fields often do not
// survive that boundary, which emptied Apps and starved tile icons.
// This object reads DesktopEntries here, in-process, and returns plain data.
QtObject {
  id: root
  property var appLibrary: null

  function list(query) {
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
      if (root.appLibrary && typeof root.appLibrary.isHiddenEntry === "function") {
        try { if (root.appLibrary.isHiddenEntry(entry)) continue } catch (e2) { }
      }
      var detail = String(entry.genericName || "")
      var hay = (name + " " + id + " " + detail).toLowerCase()
      if (q && hay.indexOf(q) < 0) continue
      out.push(root.plain(entry, id, name, detail))
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

  function plain(entry, id, name, detail) {
    var appId = id || String(entry.id || "")
    return {
      appId: appId,
      name: name || String(entry.name || ""),
      detail: detail || String(entry.genericName || ""),
      iconName: String(entry.icon || ""),
      url: TileModel.urlFromExec(String(entry.execString || "")),
      execString: String(entry.execString || "")
    }
  }

  function iconSource(name) {
    var value = String(name || "")
    if (!value) return ""
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function")
      return root.appLibrary.iconSource(value)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  function launch(desktopId, name) {
    if (root.appLibrary && typeof root.appLibrary.launch === "function") {
      root.appLibrary.launch(desktopId, name)
      return
    }
  }
}
