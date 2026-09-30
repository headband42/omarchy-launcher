function countsLine(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  if (!data.ok) return ""
  var parts = []
  var running = Number(data.running) || 0
  var stopped = Number(data.stopped) || 0
  var unhealthy = Number(data.unhealthy) || 0
  if (unhealthy > 0) parts.push(unhealthy + " unhealthy")
  parts.push(running + " up")
  if (stopped > 0) parts.push(stopped + " down")
  return parts.join(" · ")
}

function statusLabel(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  if (data.mode === "missing") return "Docker not installed"
  if (data.mode === "sudo") return "Docker needs sudo"
  if (data.mode === "error" || !data.ok) return "Docker unavailable"
  return ""
}

function statusHint(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  if (data.mode === "sudo") return "Enable sudoless Docker in Omarchy"
  return ""
}

if (typeof module !== "undefined") {
  module.exports = { countsLine: countsLine, statusLabel: statusLabel, statusHint: statusHint }
}
