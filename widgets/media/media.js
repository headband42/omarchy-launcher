// Logic for the media tile. Widget.qml imports it; test_logic.cjs requires it.
// Players are Quickshell MprisPlayer objects in QML and plain objects in tests.

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()
  var length = Number(values.length || 0)
  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.identity || "")
}

function hasTrack(player) {
  return !!player && String(player.trackTitle || "").trim().length > 0
}

// Playing beats paused, a track beats none, and a player that takes commands
// beats one that only reports.
function rank(player) {
  if (!player) return -1
  return (player.isPlaying ? 4 : 0) + (hasTrack(player) ? 2 : 0) + (player.canControl ? 1 : 0)
}

function sortPlayers(players) {
  var list = toArray(players).filter(function(p) { return !!p })
  var indexed = list.map(function(p, i) { return { p: p, i: i, r: rank(p) } })
  indexed.sort(function(a, b) { return b.r - a.r || a.i - b.i })
  return indexed.map(function(x) { return x.p })
}

// The player the tile follows: the one the user switched to while it still
// has something loaded, else the best ranked.
function pickPlayer(players, pinnedKey) {
  var list = sortPlayers(players)
  if (pinnedKey) {
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === pinnedKey && hasTrack(list[i])) return list[i]
    }
  }
  return list.length > 0 ? list[0] : null
}

// Players worth switching between: the ones with a track loaded.
function switchable(players) {
  return sortPlayers(players).filter(hasTrack)
}

function nextKey(players, currentKey) {
  var list = switchable(players)
  if (list.length === 0) return ""
  var at = -1
  for (var i = 0; i < list.length; i++) if (playerKey(list[i]) === currentKey) at = i
  return playerKey(list[(at + 1) % list.length])
}

function capitalize(text) {
  var value = String(text || "")
  return value ? value.charAt(0).toUpperCase() + value.slice(1) : ""
}

// "Firefox", "mpv", "Spotify". A bus name like
// org.mpris.MediaPlayer2.chromium.instance2200 becomes "Chromium".
function playerName(player) {
  if (!player) return ""
  var identity = String(player.identity || "").trim()
  if (identity) return identity
  var entry = String(player.desktopEntry || "").trim()
  if (entry) return capitalize(entry.split(".").pop())
  var bus = String(player.dbusName || "")
  var tail = bus.replace(/^org\.mpris\.MediaPlayer2\./, "").split(".")[0]
  return capitalize(tail)
}

function artistLine(artist, album) {
  var a = String(artist || "").trim()
  var b = String(album || "").trim()
  if (a && b) return a + " · " + b
  return a || b
}

function fmtTime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60
  var tail = (secs < 10 ? "0" : "") + secs
  if (hours > 0) return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + tail
  return minutes + ":" + tail
}

function progress(position, length) {
  var total = Number(length) || 0
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (Number(position) || 0) / total))
}

function seekTarget(x, width, length) {
  var span = Number(width) || 0
  if (span <= 0) return 0
  return progress(x, span) * Math.max(0, Number(length) || 0)
}

// One wheel notch is 5% of the player's own volume, kept in 0..1.
function stepVolume(volume, angleDelta) {
  var value = Number(volume)
  if (!isFinite(value)) value = 0
  var step = angleDelta > 0 ? 0.05 : (angleDelta < 0 ? -0.05 : 0)
  return Math.max(0, Math.min(1, Math.round((value + step) * 100) / 100))
}

if (typeof module !== "undefined") {
  module.exports = {
    toArray: toArray,
    playerKey: playerKey,
    hasTrack: hasTrack,
    rank: rank,
    sortPlayers: sortPlayers,
    pickPlayer: pickPlayer,
    switchable: switchable,
    nextKey: nextKey,
    playerName: playerName,
    artistLine: artistLine,
    fmtTime: fmtTime,
    progress: progress,
    seekTarget: seekTarget,
    stepVolume: stepVolume
  }
}
