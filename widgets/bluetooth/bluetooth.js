// Logic for the Bluetooth tile. Widget.qml imports it; test_logic.cjs requires it.
// Devices are Quickshell BluetoothDevice objects in QML and plain objects in
// tests. Rows are plain copies: a delegate that holds a BlueZ object can
// outlive it, and Quickshell crashes when it does.

// How long a connect or disconnect may take before the row stops saying so.
var PENDING_MS = 25000

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()
  var length = Number(values.length || 0)
  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function label(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
}

// BlueZ names a device it knows nothing about after its address.
function hasHumanName(device) {
  var text = label(device)
  if (!text) return false
  if (/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)) return false
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(text)) return false
  return true
}

function isAddress(value) {
  return /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(String(value || ""))
}

// A glyph for BlueZ's Icon property (a freedesktop icon name).
function glyphFor(icon) {
  var name = String(icon || "")
  if (name.indexOf("headset") >= 0 || name.indexOf("headphone") >= 0) return "󰋋"
  if (name === "audio-card" || name.indexOf("speaker") >= 0) return "󰓃"
  if (name.indexOf("mouse") >= 0) return "󰍽"
  if (name.indexOf("keyboard") >= 0) return "󰌌"
  if (name.indexOf("gaming") >= 0 || name.indexOf("joystick") >= 0) return "󰊴"
  if (name.indexOf("tablet") >= 0) return "󰓶"
  if (name.indexOf("phone") >= 0) return "󰏲"
  if (name.indexOf("computer") >= 0) return "󰟀"
  if (name.indexOf("watch") >= 0) return "󰖉"
  if (name.indexOf("camera") >= 0) return "󰄀"
  if (name.indexOf("printer") >= 0) return "󰐪"
  return "󰂯"
}

function batteryPercent(device) {
  if (!device || !device.batteryAvailable) return null
  var value = Number(device.battery)
  if (!isFinite(value)) return null
  // Quickshell reports 0..1.
  if (value <= 1) value = value * 100
  return Math.max(0, Math.min(100, Math.round(value)))
}

// The pending action for a row, while it is still young and still undone.
function pendingFor(pending, address, connected, nowMs) {
  var entry = pending && pending[address]
  if (!entry) return ""
  if ((Number(nowMs) || 0) - (Number(entry.at) || 0) > PENDING_MS) return ""
  if (entry.action === "connect" && connected) return ""
  if (entry.action === "disconnect" && !connected) return ""
  return entry.action
}

// Paired and connected devices, connected first, as plain rows. Strangers the
// adapter happens to see while discovering are left out.
function rows(devices, pending, nowMs) {
  var list = toArray(devices)
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d || !hasHumanName(d) || !isAddress(d.address) || seen[d.address]) continue
    var known = !!(d.connected || d.paired || d.bonded || d.trusted)
    if (!known) continue
    seen[d.address] = true
    out.push({
      address: String(d.address),
      name: label(d),
      glyph: glyphFor(d.icon),
      connected: !!d.connected,
      battery: batteryPercent(d),
      pending: pendingFor(pending, String(d.address), !!d.connected, nowMs)
    })
  }
  out.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    return a.name.localeCompare(b.name)
  })
  return out
}

function connectedCount(list) {
  var n = 0
  for (var i = 0; i < (list || []).length; i++) if (list[i].connected) n++
  return n
}

function status(adapter, list) {
  if (!adapter) return "no adapter"
  if (!adapter.enabled) return "off"
  var n = connectedCount(list)
  return n > 0 ? n + " connected" : "on"
}

// What a row says on the right.
function rowNote(row) {
  if (!row) return ""
  if (row.pending === "connect") return "connecting…"
  if (row.pending === "disconnect") return "disconnecting…"
  if (row.connected) return row.battery === null ? "connected" : row.battery + "%"
  return "connect"
}

function withPending(pending, address, action, nowMs) {
  var next = {}
  for (var key in pending || {}) next[key] = pending[key]
  next[address] = { action: action, at: Number(nowMs) || 0 }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    PENDING_MS: PENDING_MS,
    toArray: toArray,
    label: label,
    hasHumanName: hasHumanName,
    isAddress: isAddress,
    glyphFor: glyphFor,
    batteryPercent: batteryPercent,
    pendingFor: pendingFor,
    rows: rows,
    connectedCount: connectedCount,
    status: status,
    rowNote: rowNote,
    withPending: withPending
  }
}
