// Pure helpers for the docker widget. QML imports this file; node tests require it.

var SETUP_PATH = "Setup › Security › Sudoless Docker"

function data(sample) {
  return sample && typeof sample === "object" ? sample : {}
}

function count(value) {
  var n = Math.floor(Number(value) || 0)
  return n > 0 ? n : 0
}

// A list that crossed a QML `var` property is array-like but not an Array.
function toList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return []
}

// The headline when there are no rows to show.
function statusLabel(sample) {
  var d = data(sample)
  if (d.mode === "missing") return "Docker isn’t installed"
  if (d.mode === "sudo") return "Docker needs your password"
  if (d.mode === "idle") return "Docker is idle"
  if (d.mode === "stopped") return "Docker is stopped"
  if (d.ok && d.mode === "rows") return toList(d.rows).length ? "" : "No containers"
  return "Docker unavailable"
}

// What we could still learn without the socket.
function statusDetail(sample) {
  var d = data(sample)
  if (d.mode === "sudo") {
    if (d.daemon === "running") {
      var n = count(d.scoped)
      return n ? "Daemon running · " + n + (n === 1 ? " container" : " containers") : "Daemon running"
    }
    if (d.daemon === "idle") return "Daemon idle · starts on first use"
    return ""
  }
  if (d.mode === "idle") return "The socket starts it on first use"
  if (d.mode === "stopped") return "Neither the daemon nor its socket is running"
  if (d.mode === "error") return "The daemon did not answer"
  return ""
}

function statusHint(sample) {
  var d = data(sample)
  if (d.mode === "sudo")
    return d.pendingLogin ? "Sudoless Docker is set up. Log out and back in to use it."
      : SETUP_PATH + " skips the prompt"
  if (d.mode === "stopped") return "systemctl enable --now docker.socket"
  return ""
}

// lazydocker is worth offering whenever there is a daemon it can reach.
function canOpen(sample) {
  var mode = data(sample).mode
  return mode !== "missing" && mode !== "stopped"
}

// The big numbers over the list. Unhealthy and paused only when there are some.
function stats(sample) {
  var d = data(sample)
  if (!d.ok) return []
  var out = [{ key: "running", count: count(d.running), label: "running", tone: "ok" }]
  if (count(d.unhealthy)) out.push({ key: "unhealthy", count: count(d.unhealthy), label: "unhealthy", tone: "bad" })
  if (count(d.paused)) out.push({ key: "paused", count: count(d.paused), label: "paused", tone: "warn" })
  out.push({ key: "stopped", count: count(d.stopped), label: "stopped", tone: "off" })
  return out
}

function formatBytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return "0B"
  var units = ["B", "K", "M", "G", "T"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024
    i++
  }
  var text = n >= 10 || i === 0 ? String(Math.round(n)) : n.toFixed(1)
  return text.replace(/\.0$/, "") + units[i]
}

function formatCpu(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return "0%"
  if (n < 10) return n.toFixed(1).replace(/\.0$/, "") + "%"
  return Math.round(n) + "%"
}

// "4% · 1.2G" for the header, once anything is running.
function usageLine(sample) {
  var d = data(sample)
  if (!d.ok || !count(d.running)) return ""
  return formatCpu(d.cpu) + " · " + formatBytes(d.mem)
}

// Second line of a row: compose project, image, and published ports.
function rowDetail(row) {
  var r = row || {}
  var parts = []
  if (r.project && r.project !== r.name) parts.push(String(r.project))
  if (r.image) parts.push(String(r.image))
  var ports = toList(r.ports)
  if (ports.length) parts.push(":" + ports.join(" :"))
  return parts.join(" · ")
}

function rowUsage(row) {
  var r = row || {}
  if (!r.running || r.cpu === null || r.cpu === undefined) return ""
  return formatCpu(r.cpu) + " · " + formatBytes(r.mem)
}

// The buttons a row offers on hover, in the order they are drawn.
function actionsFor(row) {
  var r = row || {}
  if (!r.id) return []
  if (r.state === "running") return ["restart", "stop"]
  if (r.state === "restarting") return ["stop"]
  if (r.state === "exited" || r.state === "created" || r.state === "dead") return ["start"]
  return []
}

// How many rows fit, keeping a line for "+N more" when some do not.
function rowPlan(total, height, rowHeight, moreHeight) {
  var n = count(total)
  var h = Math.max(0, Number(height) || 0)
  var each = Math.max(1, Number(rowHeight) || 1)
  var all = Math.floor(h / each)
  if (n <= all) return { rows: n, more: 0 }
  var rows = Math.max(0, Math.floor((h - (Number(moreHeight) || 0)) / each))
  return { rows: rows, more: n - rows }
}

if (typeof module !== "undefined") {
  module.exports = {
    statusLabel: statusLabel,
    statusDetail: statusDetail,
    statusHint: statusHint,
    canOpen: canOpen,
    stats: stats,
    formatBytes: formatBytes,
    formatCpu: formatCpu,
    usageLine: usageLine,
    rowDetail: rowDetail,
    rowUsage: rowUsage,
    actionsFor: actionsFor,
    rowPlan: rowPlan,
    toList: toList
  }
}
