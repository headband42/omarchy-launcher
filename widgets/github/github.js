// Logic for the GitHub tile. Widget.qml imports it; test_logic.cjs requires it.

function fmtAge(nowSec, thenSec) {
  var then = Number(thenSec) || 0
  if (then <= 0) return ""
  var seconds = Math.max(0, Math.floor(Number(nowSec) - then))
  if (seconds < 3600) return Math.max(1, Math.floor(seconds / 60)) + "m"
  var hours = Math.floor(seconds / 3600)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d"
  return Math.floor(days / 30) + "mo"
}

// The CI glyph on a row: checks passed, failed, still running, or none.
function checkGlyph(pr) {
  var state = pr && pr.checks
  if (state === "success") return "󰄬"
  if (state === "failure") return "󰅖"
  if (state === "pending") return "󰔟"
  return "󰘬"
}

// What stands between the pull request and merging, most urgent first.
function note(pr) {
  if (!pr) return ""
  if (pr.draft) return "draft"
  if (pr.conflict) return "conflict"
  if (pr.checks === "failure") return "checks failed"
  if (pr.review === "changes") return "changes requested"
  if (pr.review === "approved") return pr.checks === "pending" ? "approved · checks running" : "approved"
  if (pr.checks === "pending") return "checks running"
  return ""
}

// "failure" when the row needs the user, "success" when it is ready, else "".
function tone(pr, mine) {
  if (!pr) return ""
  if (mine && (pr.conflict || pr.checks === "failure" || pr.review === "changes")) return "failure"
  if (mine && pr.review === "approved" && pr.checks !== "failure" && pr.checks !== "pending") return "success"
  return ""
}

function caption(pr, nowSec, mine) {
  if (!pr) return ""
  var parts = [String(pr.repo || "")]
  if (!mine && pr.author) parts.push(String(pr.author))
  var age = fmtAge(nowSec, pr.updated)
  if (age) parts.push(age)
  return parts.filter(function(p) { return p.length > 0 }).join(" · ")
}

// One flat list for the ListView: a header row before each non-empty group.
function rows(sample) {
  var out = []
  if (!sample || sample.state !== "ok") return out
  var groups = [
    { key: "reviews", label: "REVIEW REQUESTED", mine: false },
    { key: "mine", label: "YOUR PULL REQUESTS", mine: true }
  ]
  for (var g = 0; g < groups.length; g++) {
    var block = sample[groups[g].key] || {}
    var items = Array.isArray(block.items) ? block.items : []
    if (items.length === 0) continue
    var count = Math.max(Number(block.count) || 0, items.length)
    out.push({ kind: "header", label: groups[g].label, count: count })
    for (var i = 0; i < items.length; i++) out.push({ kind: "pr", mine: groups[g].mine, pr: items[i] })
  }
  return out
}

function waitingCount(sample) {
  if (!sample || sample.state !== "ok") return 0
  return Number((sample.reviews || {}).count) || 0
}

function notificationsLabel(sample) {
  var n = Number(sample && sample.notifications) || 0
  if (n <= 0) return ""
  return (sample.moreNotifications ? n + "+" : String(n))
}

function emptyText(sample) {
  if (!sample) return "Loading…"
  if (sample.state === "missing") return "Install the GitHub CLI, then run gh auth login"
  if (sample.state === "signin") return "Run gh auth login in a terminal"
  if (sample.state === "error") return String(sample.error || "GitHub did not answer")
  var assigned = Number(sample.assigned) || 0
  return assigned > 0 ? "No pull requests waiting · " + assigned + (assigned === 1 ? " issue" : " issues") + " assigned"
    : "Nothing waiting on you"
}

if (typeof module !== "undefined") {
  module.exports = {
    fmtAge: fmtAge,
    checkGlyph: checkGlyph,
    note: note,
    tone: tone,
    caption: caption,
    rows: rows,
    waitingCount: waitingCount,
    notificationsLabel: notificationsLabel,
    emptyText: emptyText
  }
}
