var ROWS = [
  { id: "nightlight", label: "Night light", glyph: "󰔎", command: "omarchy-toggle-nightlight" },
  { id: "stayAwake", label: "Stay awake", glyph: "󰅶", command: "omarchy-toggle-idle" },
  { id: "dnd", label: "Do not disturb", glyph: "󰂛", command: "omarchy-toggle-notification-silencing" }
]

function rowsFromSettings(value) {
  var settings = value && typeof value === "object" ? value : {}
  var picked = settings.rows
  if (!picked || picked.length === undefined) return ROWS.slice(0)
  var out = []
  for (var i = 0; i < ROWS.length; i++) {
    for (var j = 0; j < picked.length; j++) {
      if (String(picked[j]) === ROWS[i].id) {
        out.push(ROWS[i])
        break
      }
    }
  }
  return out
}

function settingsFromRows(ids) {
  var wanted = {}
  var count = 0
  for (var i = 0; i < ids.length; i++) {
    var id = String(ids[i] || "")
    if (!wanted[id]) count++
    wanted[id] = true
  }
  if (count >= ROWS.length) return {}
  var rows = []
  for (var j = 0; j < ROWS.length; j++) {
    if (wanted[ROWS[j].id]) rows.push(ROWS[j].id)
  }
  return { rows: rows }
}

if (typeof module !== "undefined") {
  module.exports = { ROWS: ROWS, rowsFromSettings: rowsFromSettings, settingsFromRows: settingsFromRows }
}
