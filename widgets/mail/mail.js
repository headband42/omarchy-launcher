// Logic for the mail tile. Widget.qml and Settings.qml import it; test_logic.cjs requires it.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var VIEWS = ["primary", "inbox", "important"]
var VIEW_LABELS = { primary: "Primary", inbox: "Inbox", important: "Important" }
// A message this new makes the header's dot pulse.
var FRESH_SECONDS = 600

function accounts(sample) {
  return sample && Array.isArray(sample.accounts) ? sample.accounts : []
}

// "now", "12m", "3h", then the weekday for this week, then the date.
function fmtAge(nowSec, thenSec) {
  var then = Number(thenSec) || 0
  if (then <= 0) return ""
  var seconds = Math.max(0, Math.floor(Number(nowSec) - then))
  if (seconds < 60) return "now"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h"
  var d = new Date(then * 1000)
  if (seconds < 6 * 86400) return DAYS[d.getDay()]
  var now = new Date(Number(nowSec) * 1000)
  var label = MONTHS[d.getMonth()] + " " + d.getDate()
  return d.getFullYear() === now.getFullYear() ? label : label + " " + d.getFullYear()
}

function hiddenKey(accountId, uid) {
  return String(accountId) + ":" + String(uid)
}

// Messages still on the tile: not marked read in this session.
function visibleMessages(account, hidden) {
  var list = Array.isArray(account && account.messages) ? account.messages : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (!(hidden && hidden[hiddenKey(account.id, list[i].uid)])) out.push(list[i])
  }
  return out
}

function unreadOf(account, hidden) {
  var all = Array.isArray(account && account.messages) ? account.messages.length : 0
  var gone = all - visibleMessages(account, hidden).length
  return Math.max(0, (Number(account && account.unread) || 0) - gone)
}

function totalUnread(sample, hidden) {
  var list = accounts(sample)
  var total = 0
  for (var i = 0; i < list.length; i++) total += unreadOf(list[i], hidden)
  return total
}

// The header: the provider when every account is on one, else MAIL.
function title(sample) {
  var list = accounts(sample)
  if (list.length === 0) return "MAIL"
  var name = String(list[0].providerName || "Mail")
  for (var i = 1; i < list.length; i++) {
    if (String(list[i].providerName || "Mail") !== name) return "MAIL"
  }
  return name.toUpperCase()
}

function unreadLabel(count) {
  var n = Number(count) || 0
  if (n <= 0) return ""
  return (n > 999 ? "999+" : String(n)) + " unread"
}

// One flat list for the ListView. An account row heads each account when
// there are several, or when the only one has a problem but old mail to show.
function rows(sample, hidden) {
  var out = []
  var list = accounts(sample)
  var many = list.length > 1
  for (var i = 0; i < list.length; i++) {
    var a = list[i]
    var messages = visibleMessages(a, hidden)
    var unread = unreadOf(a, hidden)
    var problem = a.ok === false ? String(a.error || "Not answering") : ""
    if (many || (problem && messages.length > 0)) {
      out.push({ kind: "account", account: String(a.id), label: String(a.name || a.address || ""), count: unread,
        error: problem, web: String(a.web || "") })
    }
    var canRead = a.ok !== false && Number(a.uidvalidity) > 0
    for (var j = 0; j < messages.length; j++) {
      out.push({ kind: "message", account: String(a.id), uidvalidity: Number(a.uidvalidity) || 0, canRead: canRead,
        message: messages[j], web: String(a.web || "") })
    }
    var more = unread - messages.length
    if (more > 0 && messages.length > 0) out.push({ kind: "more", account: String(a.id), count: more, web: String(a.web || "") })
  }
  return out
}

// Where a row's click goes: the conversation, else the account's webmail.
function target(row) {
  if (!row) return ""
  if (row.kind === "message" && row.message && row.message.link) return String(row.message.link)
  return String(row.web || "")
}

function emptyText(sample) {
  if (!sample) return "Loading…"
  var list = accounts(sample)
  if (list.length === 0) return "Add a mail account with the gear"
  for (var i = 0; i < list.length; i++) {
    if (list[i].ok === false) return (list.length > 1 ? String(list[i].name || list[i].address) + ": " : "") + String(list[i].error || "Not answering")
  }
  if (list.length === 1 && list[0].view === "primary") return "Nothing new in Primary"
  if (list.length === 1 && list[0].view === "important") return "Nothing new and important"
  return "No unread mail"
}

function emptyGlyph(sample) {
  var list = accounts(sample)
  if (!sample || list.length === 0) return "󰇮"
  for (var i = 0; i < list.length; i++) if (list[i].ok === false) return "󰀦"
  return "󰄬"
}

function newestDate(sample, hidden) {
  var newest = 0
  var list = accounts(sample)
  for (var i = 0; i < list.length; i++) {
    var messages = visibleMessages(list[i], hidden)
    for (var j = 0; j < messages.length; j++) newest = Math.max(newest, Number(messages[j].date) || 0)
  }
  return newest
}

function fresh(sample, hidden, nowSec) {
  var newest = newestDate(sample, hidden)
  return newest > 0 && Number(nowSec) - newest < FRESH_SECONDS
}

function viewLabel(view) {
  return VIEW_LABELS[view] || "Inbox"
}

function nextView(view) {
  var i = VIEWS.indexOf(String(view))
  return VIEWS[(i + 1) % VIEWS.length]
}

// The last reply the sampler kept, for a draw before the first poll lands.
function fromCache(raw) {
  var data = null
  try { data = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!data || typeof data !== "object" || data.ok !== true) return null
  if (!Array.isArray(data.accounts) || data.accounts.length === 0) return null
  return data
}

if (typeof module !== "undefined") {
  module.exports = {
    FRESH_SECONDS: FRESH_SECONDS,
    fmtAge: fmtAge,
    hiddenKey: hiddenKey,
    visibleMessages: visibleMessages,
    unreadOf: unreadOf,
    totalUnread: totalUnread,
    title: title,
    unreadLabel: unreadLabel,
    rows: rows,
    target: target,
    emptyText: emptyText,
    emptyGlyph: emptyGlyph,
    fresh: fresh,
    viewLabel: viewLabel,
    nextView: nextView,
    fromCache: fromCache
  }
}
