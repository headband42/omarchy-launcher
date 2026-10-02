// Logic for the Spotify tile. Widget.qml imports it; test_spotify.cjs requires it.
// Players are Quickshell MprisPlayer objects in QML and plain objects in tests.

function playerIdentity(player) {
  if (!player) return ""
  return [player.dbusName, player.desktopEntry, player.identity].join(" ").toLowerCase()
}

// OmaSpotify's backend is librespot and announces itself as
// "OmaSpotify (librespot)" with desktop entry "omaspotify".
function isLocalEngine(player) {
  var identity = playerIdentity(player)
  return identity.indexOf("librespot") !== -1 || identity.indexOf("omaspotify") !== -1
}

// The official client registers as "spotify". A browser tab playing
// open.spotify.com reports the browser's name and is left out.
function isSpotifyPlayer(player) {
  var identity = playerIdentity(player)
  return identity.indexOf("spotify") !== -1 || identity.indexOf("librespot") !== -1
}

// Whatever is playing wins, then OmaSpotify over another Spotify client.
function pickPlayer(players) {
  var list = players || []
  var best = null
  var bestRank = -1
  for (var i = 0; i < list.length; i++) {
    var player = list[i]
    if (!isSpotifyPlayer(player)) continue
    var rank = (player.isPlaying ? 2 : 0) + (isLocalEngine(player) ? 1 : 0)
    if (rank > bestRank) {
      best = player
      bestRank = rank
    }
  }
  return best
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

// Seconds for a click at x on a bar that is width wide.
function seekTarget(x, width, length) {
  var span = Number(width) || 0
  if (span <= 0) return 0
  return progress(x, span) * Math.max(0, Number(length) || 0)
}

// Spotify's repeat button order: off, then the whole context, then this track.
// QML passes MprisLoopState values so this file does not need the enum.
function nextLoop(state, none, playlist, track) {
  if (state === none) return playlist
  if (state === playlist) return track
  return none
}

if (typeof module !== "undefined") {
  module.exports = {
    isLocalEngine: isLocalEngine,
    isSpotifyPlayer: isSpotifyPlayer,
    pickPlayer: pickPlayer,
    fmtTime: fmtTime,
    progress: progress,
    seekTarget: seekTarget,
    nextLoop: nextLoop
  }
}
