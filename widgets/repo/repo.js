function countsLine(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  if (!data.ok) return ""
  var parts = []
  var ahead = Number(data.ahead) || 0
  var behind = Number(data.behind) || 0
  if (ahead > 0 || behind > 0) {
    var marks = []
    if (ahead > 0) marks.push("+" + ahead)
    if (behind > 0) marks.push("-" + behind)
    parts.push(marks.join(" "))
  }
  if (Number(data.dirty) > 0) parts.push(data.dirty + " changed")
  if (Number(data.untracked) > 0) parts.push(data.untracked + " new")
  if (Number(data.conflicted) > 0) parts.push(data.conflicted + " conflicted")
  return parts.join(" · ")
}

function branchLine(sample) {
  var data = sample && typeof sample === "object" ? sample : {}
  if (!data.ok) return ""
  if (data.detached) return "detached HEAD"
  return String(data.branch || "")
}

if (typeof module !== "undefined") {
  module.exports = { countsLine: countsLine, branchLine: branchLine }
}
