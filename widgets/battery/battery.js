function fmtDuration(minutes) {
  var total = Math.round(Number(minutes) || 0)
  if (total <= 0) return ""
  var hours = Math.floor(total / 60)
  var rest = total % 60
  if (hours <= 0) return rest + "m"
  if (rest <= 0) return hours + "h"
  return hours + "h " + rest + "m"
}

function timeLine(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  var duration = fmtDuration(data.minutesLeft)
  var state = String(data.state || "")
  if (state === "charging") return duration ? duration + " to full" : "charging"
  if (state === "fully-charged") return "charged"
  if (duration) return duration + " left"
  if (data.onAc) return "on AC"
  return ""
}

function profileLabel(id) {
  var text = String(id || "").replace(/-/g, " ")
  if (!text) return ""
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function nextProfile(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  var list = data.profiles || []
  if (list.length < 2) return ""
  var index = -1
  for (var i = 0; i < list.length; i++) {
    if (String(list[i]) === String(data.profile || "")) index = i
  }
  return String(list[(index + 1) % list.length])
}

if (typeof module !== "undefined") {
  module.exports = { fmtDuration: fmtDuration, timeLine: timeLine, profileLabel: profileLabel, nextProfile: nextProfile }
}
