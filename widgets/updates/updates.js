function fmtAgo(nowMs, thenSec) {
  var then = Number(thenSec) || 0
  if (then <= 0) return ""
  var seconds = Math.floor((Number(nowMs) || 0) / 1000) - then
  if (seconds < 0) seconds = 0
  if (seconds < 60) return "just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(months / 12) + "y ago"
}

if (typeof module !== "undefined") {
  module.exports = { fmtAgo: fmtAgo }
}
