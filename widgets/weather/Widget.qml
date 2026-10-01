import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "weather.js" as Weather
import "../_kit/kit.js" as Kit

Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  property var resolvedLocation: null
  property bool loaded: false
  property bool haveWeather: false
  property bool stale: false
  property real phase: 0
  property bool settled: false
  property int settleAttempts: 0
  property string probePhase: "idle"
  property string pendingLocationKey: ""
  property string lastFetchedKey: ""
  property string lastSeenLocationKey: ""

  readonly property var options: Weather.normalizedSettings(root.tile && root.tile.settings)
  readonly property var configuredLocation: root.options.location
  readonly property var activeLocation: root.configuredLocation || root.resolvedLocation
  readonly property var current: root.sample && root.sample.ok !== false && root.sample.current ? root.sample.current : null
  readonly property var hourly: root.sample && root.sample.hourly && root.sample.hourly.length ? root.sample.hourly : []
  readonly property var daily: root.sample && root.sample.daily && root.sample.daily.length ? root.sample.daily : []
  readonly property var units: root.options.units
  readonly property bool atmosphereEnabled: root.options.atmosphere !== false
  readonly property var air: root.sample && root.sample.air ? root.sample.air : null
  // When the last sample arrived, for the moon phase.
  property real sampledAt: Date.now()
  readonly property string locationKey: {
    var place = root.activeLocation || {}
    var latitude = place.latitude === undefined ? "" : place.latitude
    var longitude = place.longitude === undefined ? "" : place.longitude
    return String(latitude) + "," + String(longitude)
  }
  readonly property int code: root.current ? Math.round(Number(root.current.code)) : -1
  readonly property bool snowing: (root.code >= 71 && root.code <= 77) || root.code === 85 || root.code === 86
  // The sky behind the tile, one look per kind of weather (Weather.SKIES).
  readonly property string skyKind: Weather.skyKind(root.code, root.current ? root.current.isDay : 1)
  readonly property var skyLook: Weather.sky(root.skyKind)
  readonly property var fall: Weather.particles(root.skyLook.particles)
  // A light theme tints less so dark text stays readable.
  readonly property real skyStrength: root.mapStyle === "dark" ? 1 : 0.55
  // At 1080p / scale 1 / text 11, tileSize is ~270–280px tall.
  // compact: denser hero; slightly fewer hour columns
  // roomy: denser DETAILS grid (gusts/pressure/vis)
  // The bottom half rotates through the panels left on in settings.
  readonly property bool compact: root.height < Style.space(250)
  // ~270-280px tiles stay mid (3x2 DETAILS); only taller tiles get 4x2.
  readonly property bool roomy: root.height >= Style.space(340)
  readonly property int chartCount: Weather.hourlyCount(Math.max(0, root.width - Style.space(28)))
  readonly property var chartHours: Weather.hourColumns(root.current, root.hourly, root.chartCount)
  readonly property bool failed: root.loaded && !root.haveWeather
  readonly property int heroPx: Math.max(Style.font.heading, Math.round(Math.min(root.width * 0.2, root.height * (root.compact ? 0.22 : 0.25))))
  readonly property int glyphPx: Math.max(Style.space(30), Math.round(root.heroPx * 0.9))
  readonly property int tinyPx: Math.max(8, Style.font.caption - 2)
  readonly property color rainColor: Qt.tint(root.foreground, Qt.rgba(0.36, 0.66, 1, 0.72))
  readonly property color cardColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
  readonly property color sunColor: "#f6c453"

  // Nerd fonts draw weather icons at very different sizes: a Mono variant
  // squeezes them into one cell. Scale by the measured width of a cloud so
  // they look alike in either.
  TextMetrics {
    id: glyphProbe
    font.family: root.fontFamily
    font.pixelSize: 100
    text: "\ue312"
  }
  readonly property real glyphScale: {
    var width = glyphProbe.tightBoundingRect.width
    return width > 1 ? Math.max(1, Math.min(2.4, 85 / width)) : 1
  }
  function glyphSize(px) {
    return Math.max(1, Math.round(px * root.glyphScale))
  }

  readonly property var panels: root.options.panels
  property int panelIndex: 0
  property bool panelPaused: false
  readonly property string currentPanel: root.panels[root.panelIndex % Math.max(1, root.panels.length)] || "hours"
  readonly property bool rotating: root.visible && root.current !== null && !root.panelPaused && root.panels.length > 1
  readonly property int panelInterval: root.currentPanel === "radar" ? 6500 : 4000
  // 0..1 through the current panel's turn, drawn in its page pill.
  property real dwell: 0
  readonly property bool radarEnabled: root.panels.indexOf("radar") >= 0
  readonly property bool airEnabled: root.panels.indexOf("air") >= 0

  function selectPanel(index) {
    var next = Math.max(0, Math.min(root.panels.length - 1, Math.round(Number(index))))
    root.panelIndex = next
    root.panelPaused = true
    panelPause.restart()
  }

  function restartDwell() {
    dwellAnimation.stop()
    if (!root.rotating) {
      root.dwell = root.panelPaused ? 1 : 0
      return
    }
    panelRotate.restart()
    dwellAnimation.duration = root.panelInterval
    dwellAnimation.restart()
  }

  // The old hourly Canvas chart was removed with the HOURS/DETAILS/WEEK carousel.
  // Do not call paint on that removed object — it ReferenceErrors and spams the shell log.
  function repaintAtmosphere() {
    if (atmosphere) atmosphere.requestPaint()
    if (skyArt) skyArt.requestPaint()
  }
  readonly property color skyTop: root.skyLook.top
  readonly property color skyBottom: root.skyLook.bottom

  property real displayedTemperature: 0

  function hasBoundTile() {
    var tile = root.tile
    if (!tile) return false
    if (tile.widget || tile.widgetQml) return true
    if (tile.settings) return true
    return false
  }

  function syncDisplayedTemperature() {
    if (!root.current) return
    var target = Number(root.current.temperature)
    if (root.units === "imperial") target = target * 9 / 5 + 32
    if (isFinite(target)) root.displayedTemperature = target
  }

  function applyPayload(parsed) {
    if (!parsed || parsed.ok !== true || !parsed.current) {
      if (!root.haveWeather) {
        root.sample = parsed || { ok: false, current: null, hourly: [], daily: [] }
        root.displayedTemperature = 0
      } else {
        root.stale = true
      }
      root.loaded = true
      return false
    }
    root.sample = parsed
    root.sampledAt = Date.now()
    root.resolvedLocation = parsed.location || root.resolvedLocation
    root.haveWeather = true
    root.stale = parsed.stale === true
    root.loaded = true
    root.lastFetchedKey = root.locationKey
    root.lastSeenLocationKey = root.locationKey
    root.syncDisplayedTemperature()
    return true
  }

  function buildProbeArgs(mode) {
    var args = ["/usr/bin/python3", "-u", Kit.localPath(Qt.resolvedUrl("weather.py"))]
    var place = root.configuredLocation
    if (!place && root.settled) place = root.activeLocation
    if (place && place.latitude !== undefined && place.longitude !== undefined
        && String(place.latitude).length && String(place.longitude).length) {
      args.push("--latitude", String(place.latitude))
      args.push("--longitude", String(place.longitude))
      args.push("--label", String(place.name || ""))
      if (place.timezone) args.push("--timezone", String(place.timezone))
    } else if (!root.settled) {
      return null
    }
    if (mode === "cache-only") args.push("--cache-only")
    else if (mode === "cache-first") args.push("--cache-first")
    if (!root.airEnabled) args.push("--no-air")
    return args
  }

  function locationKeyForArgs(args) {
    if (!args) return root.locationKey
    var lat = ""
    var lon = ""
    for (var i = 0; i < args.length; i++) {
      if (args[i] === "--latitude" && i + 1 < args.length) lat = String(args[i + 1])
      if (args[i] === "--longitude" && i + 1 < args.length) lon = String(args[i + 1])
    }
    return lat + "," + lon
  }

  function startProbe(mode) {
    if (!root.visible) return false
    var args = root.buildProbeArgs(mode)
    if (!args) return false
    var key = root.locationKeyForArgs(args)
    if (probe.running) {
      if (probe.key === key && probe.phase === mode) return true
      probe.again = true
      probe.pendingMode = mode
      return false
    }
    probe.again = false
    probe.pendingMode = ""
    probe.phase = mode || "live"
    probe.key = key
    probe.command = args
    probe.running = true
    return true
  }

  function refresh(mode) {
    if (!root.visible) return
    if (!root.settled && !root.configuredLocation) {
      settle.restart()
      return
    }
    var requested = mode || "live"
    if (requested === "live" && !root.haveWeather) requested = "cache-first"
    root.startProbe(requested)
  }

  function scheduleSettle() {
    root.settled = false
    root.settleAttempts = 0
    settle.restart()
  }

  function queueFollowUp(mode) {
    followUp.mode = mode || "live"
    followUp.restart()
  }

  function uvLabel(value) {
    var index = Number(value)
    if (!isFinite(index)) return "—"
    if (index < 3) return "Low " + Math.round(index)
    if (index < 6) return "Mod " + Math.round(index)
    if (index < 8) return "High " + Math.round(index)
    if (index < 11) return "V.High " + Math.round(index)
    return "Extreme"
  }

  function rainChance() {
    var peak = 0
    for (var i = 0; i < root.chartHours.length; i++) {
      var value = Number(root.chartHours[i] && root.chartHours[i].precipProbability)
      if (isFinite(value) && value > peak) peak = value
    }
    return Math.round(peak) + "%"
  }

  function today() {
    return root.daily.length ? root.daily[0] : null
  }

  function highLow() {
    var day = root.today()
    if (!day || day.high === null || day.high === undefined || day.low === null || day.low === undefined) return ""
    return "H " + Weather.temperature(day.high, root.units) + "  L " + Weather.temperature(day.low, root.units)
  }

  function sunValue() {
    var day = root.today()
    if (!day) return "—"
    var sunset = String(day.sunset || "")
    var currentTime = String((root.current && root.current.time) || "")
    if (currentTime && currentTime < sunset) return Weather.sunClock(sunset)
    var tomorrow = root.daily.length > 1 ? root.daily[1] : null
    return tomorrow && tomorrow.sunrise ? Weather.sunClock(tomorrow.sunrise) : Weather.sunClock(sunset)
  }

  function sunLabel() {
    var day = root.today()
    if (!day) return "SUN"
    var sunset = String(day.sunset || "")
    var currentTime = String((root.current && root.current.time) || "")
    return currentTime && currentTime < sunset ? "SET" : "RISE"
  }

  function currentDirection() {
    return Weather.windDirection(root.current ? root.current.windDirection : 0)
  }

  function currentWind() {
    if (!root.current) return "—"
    return Weather.speed(root.current.wind, root.units)
  }

  function currentGust() {
    if (!root.current) return "—"
    return Weather.gust(root.current.gust, root.units)
  }

  function currentPressure() {
    if (!root.current) return "—"
    return Weather.pressure(root.current.pressure, root.units)
  }

  function currentVisibility() {
    if (!root.current) return "—"
    return Weather.visibility(root.current.visibility, root.units)
  }

  function forecastDays() {
    return Weather.dailyDays(root.daily, root.compact ? 4 : 5)
  }

  function panelStats() {
    var precip = root.current ? Weather.precipitation(root.current.precipitation, root.units) : "—"
    var rows = [
      { label: "RAIN", icon: "\ue37c", value: root.rainChance() },
      // The arrow points where the wind is blowing to.
      { label: "WIND", icon: "\ue3a9", turn: root.current ? (Number(root.current.windDirection) || 0) + 180 : 0,
        value: root.currentWind() + (root.currentDirection() ? " " + root.currentDirection() : "") },
      { label: "HUMIDITY", icon: "\ue373", value: root.current ? Math.round(Number(root.current.humidity) || 0) + "%" : "—" },
      { label: "UV", icon: "\ue30d", value: root.uvLabel(root.current ? root.current.uv : null) },
      { label: "PRECIP", icon: "\ue34a", value: precip },
      { label: "GUSTS", icon: "\ue34b", value: root.currentGust() },
      { label: "PRESSURE", icon: "\ue372", value: root.currentPressure() },
      { label: "VIS", icon: "\ue35d", value: root.currentVisibility() }
    ]
    // compact (~<250): 4 stats in one row
    // mid (~270–280): 6 stats in 3×2 — fills the carousel without a sparse 4th column
    // roomy: full 8-stat 4×2 grid
    if (root.compact) return rows.slice(0, 4)
    if (!root.roomy) return [rows[0], rows[1], rows[2], rows[4], rows[5], rows[6]]
    return rows
  }

  function detailsColumns() {
    if (root.roomy) return 4
    if (root.compact) return 2
    return 3
  }

  function hourPrecip(row) {
    if (!row || row.precipProbability === null || row.precipProbability === undefined) return ""
    var chance = Number(row.precipProbability)
    if (!isFinite(chance) || chance < 10) return ""
    return Math.round(chance) + "%"
  }

  function staleHint() {
    return root.stale ? "Showing last good reading" : "Live"
  }


  readonly property string diskCachePath: {
    var key = Weather.cacheKey(root.configuredLocation)
    if (!key) return ""
    return Quickshell.env("HOME") + "/.cache/ande.launcher/weather/" + key + ".json"
  }

  function applyDiskCacheText(raw) {
    if (!raw) return false
    var envelope = null
    try { envelope = JSON.parse(raw) } catch (e) { return false }
    if (!envelope || typeof envelope !== "object") return false
    var payload = envelope.payload
    if (!payload || payload.ok !== true || !payload.current) return false
    var savedAt = Number(envelope.savedAt)
    var age = isFinite(savedAt) ? Math.max(0, (Date.now() / 1000) - savedAt) : 0
    payload = {
      ok: true,
      location: payload.location,
      current: payload.current,
      hourly: payload.hourly || [],
      daily: payload.daily || [],
      air: payload.air || null,
      units: payload.units,
      stale: age > 12 * 60,
      cached: true,
      cacheAge: Math.round(age)
    }
    return root.applyPayload(payload)
  }

  function readDiskCache() {
    if (!root.diskCachePath) return false
    if (diskCache.path !== root.diskCachePath) diskCache.path = root.diskCachePath
    if (!diskCache.path) return false
    try {
      diskCache.blockLoading = true
      var raw = diskCache.text()
      return root.applyDiskCacheText(raw)
    } catch (e) {
      return false
    }
  }

  FileView {
    id: diskCache
    path: root.diskCachePath
    watchChanges: false
    printErrors: false
    preload: false
    onLoaded: {
      if (!root.haveWeather) root.applyDiskCacheText(text())
    }
    onPathChanged: {
      if (path && path.length) reload()
    }
  }

  // Lightweight cache reader — avoids python startup under TCG when FileView misses.
  Process {
    id: cacheCat
    property string key: ""
    command: ["cat", root.diskCachePath]
    stdout: StdioCollector { id: cacheCatOut; waitForEnd: true }
    onExited: {
      if (cacheCat.key !== root.locationKey) return
      if (!root.haveWeather) root.applyDiskCacheText(cacheCatOut.text || "")
    }
  }

  function startCacheCat() {
    if (!root.diskCachePath || !root.visible) return false
    if (cacheCat.running) return true
    cacheCat.key = root.locationKey
    cacheCat.command = ["cat", root.diskCachePath]
    cacheCat.running = true
    return true
  }

  Process {
    id: probe
    property bool again: false
    property string key: ""
    property string phase: "idle"
    property string pendingMode: ""
    command: ["/usr/bin/python3", "-u", Kit.localPath(Qt.resolvedUrl("weather.py"))]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      var finishedKey = probe.key
      var finishedPhase = probe.phase

      if (finishedKey !== root.locationKey) {
        probe.again = false
        if (probe.pendingMode) {
          var pending = probe.pendingMode
          probe.pendingMode = ""
          root.queueFollowUp(pending)
        } else if (root.visible && root.settled) {
          root.queueFollowUp("cache-first")
        }
        return
      }

      var parsed = null
      try { parsed = JSON.parse(probeOut.text || "") } catch (e) { parsed = null }

      if (finishedPhase === "cache-only" || finishedPhase === "cache-first") {
        if (parsed && parsed.ok === true && parsed.current) root.applyPayload(parsed)
        if (probe.again || probe.pendingMode) {
          var nextMode = probe.pendingMode || "live"
          probe.again = false
          probe.pendingMode = ""
          root.queueFollowUp(nextMode)
          return
        }
        if (root.visible) root.queueFollowUp("live")
        return
      }

      root.applyPayload(parsed)
      if (probe.again || probe.pendingMode) {
        var resume = probe.pendingMode || "live"
        probe.again = false
        probe.pendingMode = ""
        root.queueFollowUp(resume)
        return
      }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: followUp
    property string mode: "live"
    interval: 16
    onTriggered: root.startProbe(followUp.mode)
  }

  Timer {
    id: settle
    interval: 60
    onTriggered: {
      if (!root.visible) return
      root.lastSeenLocationKey = root.locationKey
      if (root.configuredLocation) {
        root.settled = true
        root.settleAttempts = 0
        if (!(root.haveWeather && root.lastFetchedKey === root.locationKey)) {
          if (!root.readDiskCache()) {
            root.startCacheCat()
            root.refresh("cache-first")
          } else root.queueFollowUp("live")
        }
        return
      }
      if (root.hasBoundTile() || root.settleAttempts >= 5) {
        root.settled = true
        root.settleAttempts = 0
        if (!(root.haveWeather && root.lastFetchedKey === root.locationKey)) {
          if (!root.readDiskCache()) {
            root.startCacheCat()
            root.refresh("cache-first")
          } else root.queueFollowUp("live")
        }
        return
      }
      root.settleAttempts += 1
      root.settled = false
      settle.restart()
    }
  }

  Timer {
    id: poll
    interval: 600000
    onTriggered: root.refresh("live")
  }

  Timer {
    id: panelRotate
    interval: root.panelInterval
    repeat: true
    running: root.rotating
    onTriggered: root.panelIndex = (root.panelIndex + 1) % Math.max(1, root.panels.length)
  }

  NumberAnimation {
    id: dwellAnimation
    target: root
    property: "dwell"
    from: 0
    to: 1
  }

  // Radar frames and map tiles, fetched only while the radar panel is on.
  property var radar: null
  property int radarFrame: 0
  readonly property var radarFrames: root.radar && root.radar.ok && root.radar.frames ? root.radar.frames : []
  readonly property int shownFrame: Math.max(0, Math.min(root.radarFrame, root.radarFrames.length - 1))
  // A light foreground means a dark theme, so a dark map.
  readonly property string mapStyle: (0.299 * root.foreground.r + 0.587 * root.foreground.g + 0.114 * root.foreground.b) > 0.5 ? "dark" : "light"
  readonly property var radarArgs: {
    var place = root.activeLocation
    if (!place || place.latitude === undefined || place.longitude === undefined) return []
    if (!String(place.latitude).length || !String(place.longitude).length) return []
    return ["--radar", "--latitude", String(place.latitude), "--longitude", String(place.longitude),
      "--style", root.mapStyle, "--zoom", String(root.options.radarZoom)]
  }

  Poller {
    id: radarPoller
    script: Qt.resolvedUrl("weather.py")
    args: root.radarArgs
    interval: 300000
    active: root.visible && root.radarEnabled && root.radarArgs.length > 0
    onSampled: function(data) {
      if (data && (data.ok === true || !root.radar || root.radar.ok !== true)) root.radar = data
    }
  }

  Timer {
    id: radarPlay
    // Hold on the newest frame, then play the last hour through.
    interval: root.shownFrame >= root.radarFrames.length - 1 ? 1500 : 450
    repeat: true
    running: root.visible && root.currentPanel === "radar" && root.radarFrames.length > 1
    onTriggered: root.radarFrame = (root.shownFrame + 1) % root.radarFrames.length
  }

  Timer {
    id: panelPause
    interval: 20000
    repeat: false
    onTriggered: root.panelPaused = false
  }

  NumberAnimation on phase {
    from: 0
    to: 1
    duration: root.skyLook.particles === "snow" ? 5200 : 2600
    loops: Animation.Infinite
    running: root.visible && root.atmosphereEnabled && root.fall !== null
  }

  Behavior on displayedTemperature {
    NumberAnimation { duration: 650; easing.type: Easing.OutCubic }
  }

  Item {
    id: sky
    anchors.fill: parent
    visible: root.atmosphereEnabled

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(root.skyTop.r, root.skyTop.g, root.skyTop.b, 0.62 * root.skyStrength) }
        GradientStop { position: 1; color: Qt.rgba(root.skyBottom.r, root.skyBottom.g, root.skyBottom.b, 0.42 * root.skyStrength) }
      }
    }

    // Glow, stars, and clouds. They only change with the kind of sky.
    Canvas {
      id: skyArt
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (width < 2 || height < 2) return
        var look = root.skyLook
        var strength = root.skyStrength
        var night = root.skyKind.indexOf("night") >= 0
        if (look.glow) {
          var tone = Qt.lighter(look.glow, 1)
          var alpha = (look.glowAlpha || 0) * strength
          var cx = width * 0.84
          var cy = height * 0.1
          var glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(width, height) * 0.8)
          glow.addColorStop(0, Qt.rgba(tone.r, tone.g, tone.b, alpha))
          glow.addColorStop(0.3, Qt.rgba(tone.r, tone.g, tone.b, alpha * 0.35))
          glow.addColorStop(1, Qt.rgba(tone.r, tone.g, tone.b, 0))
          ctx.fillStyle = glow
          ctx.fillRect(0, 0, width, height)
        }
        for (var i = 0; i < (look.stars || 0); i++) {
          ctx.beginPath()
          ctx.arc(((i * 73 + 11) % 97) / 97 * width, ((i * 41 + 7) % 53) / 53 * height * 0.6,
            0.5 + (i % 3) * 0.45, 0, Math.PI * 2)
          ctx.fillStyle = Qt.rgba(1, 1, 1, (0.25 + (i % 4) * 0.13) * strength)
          ctx.fill()
        }
        var cloudAlpha = (night ? 0.05 : (root.skyKind === "overcast" ? 0.07 : 0.09)) * strength
        for (var j = 0; j < (look.clouds || 0); j++) {
          var bx = ((j * 37 + 13) % 89) / 89 * width * 1.1 - width * 0.05
          var by = height * (0.05 + ((j * 29 + 5) % 17) / 17 * 0.32)
          var radius = width * (0.22 + (j % 3) * 0.07)
          var puff = ctx.createRadialGradient(bx, by, 0, bx, by, radius)
          puff.addColorStop(0, Qt.rgba(1, 1, 1, cloudAlpha))
          puff.addColorStop(0.6, Qt.rgba(1, 1, 1, cloudAlpha * 0.5))
          puff.addColorStop(1, Qt.rgba(1, 1, 1, 0))
          ctx.fillStyle = puff
          ctx.fillRect(bx - radius, by - radius, radius * 2, radius * 2)
        }
      }
    }

    // Fog: soft bands drifting across.
    Repeater {
      model: root.skyLook.mist ? 3 : 0

      Rectangle {
        id: mistBand
        required property int index
        width: sky.width * 1.6
        height: sky.height * (0.22 + mistBand.index * 0.06)
        y: sky.height * (0.16 + mistBand.index * 0.27)
        x: -sky.width * 0.3
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.11 * root.skyStrength) }
          GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }

        SequentialAnimation on x {
          running: root.visible && root.atmosphereEnabled
          loops: Animation.Infinite
          NumberAnimation { from: -sky.width * (0.5 - mistBand.index * 0.1); to: -sky.width * (0.1 + mistBand.index * 0.05); duration: 9000 + mistBand.index * 2600; easing.type: Easing.InOutSine }
          NumberAnimation { from: -sky.width * (0.1 + mistBand.index * 0.05); to: -sky.width * (0.5 - mistBand.index * 0.1); duration: 9000 + mistBand.index * 2600; easing.type: Easing.InOutSine }
        }
      }
    }

    // Rain, drizzle, sleet, and snow.
    Canvas {
      id: atmosphere
      anchors.fill: parent
      visible: root.fall !== null
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var fall = root.fall
        if (!fall || width < 2 || height < 2) return
        var ink = Qt.tint(root.foreground, Qt.rgba(0.6, 0.8, 1, 0.35))
        var snow = root.skyLook.particles === "snow"
        var sleet = root.skyLook.particles === "sleet"
        for (var i = 0; i < fall.count; i++) {
          var x = ((i * 47 + 19) % 101) / 100 * width
          var travel = (root.phase * fall.speed + (i * 0.137) % 1) % 1
          var y = travel * (height + 30) - 15
          if (snow) {
            ctx.beginPath()
            ctx.arc(x + Math.sin(i * 1.7 + travel * 7) * 5, y, 1.1 + (i % 3) * 0.55, 0, Math.PI * 2)
            ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, fall.alpha * (0.6 + (i % 2) * 0.4))
            ctx.fill()
            continue
          }
          ctx.beginPath()
          ctx.moveTo(x, y)
          ctx.lineTo(x - fall.slant, y + fall.length)
          ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, fall.alpha)
          ctx.lineWidth = fall.length > 10 ? 1.3 : 1
          ctx.stroke()
          if (sleet) {
            ctx.beginPath()
            ctx.arc(x - fall.slant, y + fall.length + 1.5, 1.3, 0, Math.PI * 2)
            ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, fall.alpha + 0.15)
            ctx.fill()
          }
        }
      }
    }

    // Thunderstorms: a flicker every few seconds.
    Rectangle {
      anchors.fill: parent
      visible: root.skyLook.lightning === true
      opacity: 0
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.9 * root.skyStrength) }
        GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0) }
      }

      SequentialAnimation on opacity {
        running: root.visible && root.atmosphereEnabled && root.skyLook.lightning === true
        loops: Animation.Infinite
        alwaysRunToEnd: true
        PauseAnimation { duration: 3600 }
        NumberAnimation { to: 0.38; duration: 50 }
        NumberAnimation { to: 0.06; duration: 90 }
        NumberAnimation { to: 0.26; duration: 40 }
        NumberAnimation { to: 0; duration: 480; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 2600 }
      }
    }
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    anchors.topMargin: Style.space(12)
    anchors.bottomMargin: Style.space(10)
    visible: root.current !== null

    Item {
      id: header
      width: parent.width
      height: Style.font.caption + Style.space(5)

      Text {
        anchors.left: parent.left
        anchors.right: liveRow.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String((root.activeLocation && root.activeLocation.name) || "Weather").toUpperCase()
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        elide: Text.ElideRight
      }

      Row {
        id: liveRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.compact
          textFormat: Text.PlainText
          text: root.sunLabel() + " " + root.sunValue()
          color: root.foreground
          opacity: 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.stale
          textFormat: Text.PlainText
          text: "STALE"
          color: Color.urgent
          opacity: 0.85
          font.family: root.fontFamily
          font.pixelSize: root.tinyPx
          font.weight: Font.DemiBold
          font.letterSpacing: 0.5
        }

        Rectangle {
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: root.stale ? Color.urgent : Color.accent
          opacity: root.stale ? 0.55 : 1
        }
      }
    }

    Item {
      id: hero
      width: parent.width
      height: root.compact ? Style.space(68) : (root.roomy ? Style.space(92) : Style.space(72))
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Text {
          id: heroGlyph
          anchors.verticalCenter: parent.verticalCenter
          width: root.glyphPx
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: Weather.glyph(root.code, root.current ? root.current.isDay : 1)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.glyphSize(root.glyphPx * 0.92)
        }

        Text {
          id: temperature
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Math.round(root.displayedTemperature) + "°"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.heroPx
          font.weight: Font.DemiBold
          font.features: ({ "tnum": 1 })
        }

        Column {
          width: Math.max(0, hero.width - root.glyphPx - temperature.implicitWidth - Style.space(20))
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String((root.current && root.current.label) || "Weather")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Feels " + Weather.temperature(root.current ? root.current.apparent : null, root.units)
            color: root.foreground
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            visible: !root.compact
            width: parent.width
            textFormat: Text.PlainText
            text: root.highLow()
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }

    Item {
      id: carousel
      width: parent.width
      anchors.top: hero.bottom
      anchors.topMargin: Style.space(4)
      anchors.bottom: parent.bottom
      visible: root.current !== null

      Item {
        id: panelHeader
        width: parent.width
        height: Style.font.caption + Style.space(4)
        z: 2

        Text {
          anchors.left: parent.left
          anchors.right: pages.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Weather.panelTitle(root.currentPanel)
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: root.tinyPx
          font.weight: Font.Medium
          font.letterSpacing: 0.8
          elide: Text.ElideRight
        }

        // One pill per panel. The current one is wider and fills over its turn.
        Row {
          id: pages
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          visible: root.panels.length > 1

          Repeater {
            model: root.panels.length

            Item {
              id: page
              required property int index
              readonly property bool current: index === root.panelIndex % Math.max(1, root.panels.length)
              width: page.current ? Style.space(16) : 5
              height: 5
              anchors.verticalCenter: parent.verticalCenter
              Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.foreground
                opacity: page.current ? 0.28 : 0.22
              }

              Rectangle {
                visible: page.current
                width: Math.max(height, parent.width * root.dwell)
                height: parent.height
                radius: height / 2
                color: root.foreground
                opacity: 0.8
              }

              MouseArea {
                anchors.centerIn: parent
                width: parent.width + Style.space(4)
                height: Style.space(22)
                z: 3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse.accepted = true
                onClicked: {
                  mouse.accepted = true
                  root.selectPanel(page.index)
                }
              }
            }
          }
        }
      }

      Item {
        id: panelStage
        width: parent.width
        anchors.top: panelHeader.bottom
        anchors.topMargin: Style.space(6)
        anchors.bottom: parent.bottom

        // HOURS: now, then the coming hours, with temperatures riding a curve.
        Item {
          id: hoursPanel
          readonly property bool shown: root.currentPanel === "hours"
          anchors.fill: parent
          opacity: hoursPanel.shown ? 1 : 0
          visible: opacity > 0.01
          transform: Translate { x: (hoursPanel.shown ? 1 : -1) * (1 - hoursPanel.opacity) * Style.space(10) }
          Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          readonly property int count: root.chartHours.length
          readonly property real column: width / Math.max(1, count)
          readonly property int timeHeight: root.tinyPx + Style.space(4)
          readonly property int glyphHeight: Style.space(root.compact ? 18 : 22)
          readonly property int tempHeight: Style.font.caption + Style.space(3)
          readonly property int rainHeight: root.tinyPx + Style.space(4)
          readonly property int curveHeight: Math.max(tempHeight + Style.space(12),
            Math.min(Math.max(tempHeight + Style.space(42), height * 0.42), height - timeHeight - glyphHeight - rainHeight - Style.space(8)))
          readonly property int stackHeight: timeHeight + glyphHeight + curveHeight + rainHeight
          readonly property int stackTop: Math.max(Style.space(3), Math.round((height - stackHeight) / 2))
          readonly property int curveTop: stackTop + timeHeight + glyphHeight
          readonly property var points: Weather.chartPoints(root.chartHours, root.units, width, curveHeight, tempHeight + Style.space(2), Style.space(4))
          onPointsChanged: hoursCurve.requestPaint()

          Rectangle {
            visible: hoursPanel.count > 0
            x: 0
            y: hoursPanel.stackTop - Style.space(3)
            width: hoursPanel.column
            height: hoursPanel.stackHeight + Style.space(4)
            radius: Style.space(6)
            color: root.cardColor
          }

          Canvas {
            id: hoursCurve
            x: 0
            y: hoursPanel.curveTop
            width: hoursPanel.width
            height: hoursPanel.curveHeight
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              var pts = hoursPanel.points
              if (pts.length < 2) return
              var fg = root.foreground
              function trace() {
                ctx.moveTo(pts[0].x, pts[0].y)
                for (var i = 1; i < pts.length; i++) {
                  var mx = (pts[i - 1].x + pts[i].x) / 2
                  var my = (pts[i - 1].y + pts[i].y) / 2
                  ctx.quadraticCurveTo(pts[i - 1].x, pts[i - 1].y, mx, my)
                }
                ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y)
              }
              var fill = ctx.createLinearGradient(0, 0, 0, height)
              fill.addColorStop(0, Qt.rgba(fg.r, fg.g, fg.b, 0.16))
              fill.addColorStop(1, Qt.rgba(fg.r, fg.g, fg.b, 0))
              ctx.beginPath()
              trace()
              ctx.lineTo(pts[pts.length - 1].x, height)
              ctx.lineTo(pts[0].x, height)
              ctx.closePath()
              ctx.fillStyle = fill
              ctx.fill()
              ctx.beginPath()
              trace()
              ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.5)
              ctx.lineWidth = 1.5
              ctx.stroke()
              for (var j = 0; j < pts.length; j++) {
                ctx.beginPath()
                ctx.arc(pts[j].x, pts[j].y, j === 0 ? 2.6 : 1.8, 0, Math.PI * 2)
                ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, j === 0 ? 1 : 0.75)
                ctx.fill()
              }
            }
          }

          Repeater {
            model: root.chartHours

            Item {
              id: hourColumn
              required property var modelData
              required property int index
              readonly property var point: hoursPanel.points[index] || ({ y: 0 })
              x: index * hoursPanel.column
              width: hoursPanel.column
              height: hoursPanel.height

              Text {
                y: hoursPanel.stackTop
                width: parent.width
                height: hoursPanel.timeHeight
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: hourColumn.index === 0 && hourColumn.modelData.time === "now" ? "Now" : Weather.clock(hourColumn.modelData.time, true)
                color: root.foreground
                opacity: hourColumn.index === 0 ? 0.9 : 0.5
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
                font.weight: hourColumn.index === 0 ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                y: hoursPanel.stackTop + hoursPanel.timeHeight
                width: parent.width
                height: hoursPanel.glyphHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: Weather.glyph(hourColumn.modelData.code, hourColumn.modelData.isDay)
                color: root.foreground
                opacity: 0.9
                font.family: root.fontFamily
                font.pixelSize: root.glyphSize(Style.space(root.compact ? 14 : 16))
              }

              Text {
                y: hoursPanel.curveTop + hourColumn.point.y - hoursPanel.tempHeight - Style.space(1)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Weather.temperature(hourColumn.modelData.temperature, root.units)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.max(10, Style.font.caption)
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
              }

              Text {
                y: hoursPanel.curveTop + hoursPanel.curveHeight + Style.space(2)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.hourPrecip(hourColumn.modelData)
                color: root.rainColor
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
                font.weight: Font.Medium
                visible: text.length > 0
              }
            }
          }
        }

        // DETAILS: a card per reading.
        Item {
          id: detailsPanel
          readonly property bool shown: root.currentPanel === "details"
          anchors.fill: parent
          opacity: detailsPanel.shown ? 1 : 0
          visible: opacity > 0.01
          transform: Translate { x: (detailsPanel.shown ? 1 : -1) * (1 - detailsPanel.opacity) * Style.space(10) }
          Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          readonly property var stats: root.panelStats()
          readonly property int columns: root.detailsColumns()
          readonly property int rows: Math.max(1, Math.ceil(stats.length / columns))
          readonly property int gap: Style.space(5)
          readonly property real cellWidth: (width - gap * (columns - 1)) / columns
          readonly property real cellHeight: Math.max(0, Math.min(Style.space(root.roomy ? 78 : 62), (height - gap * (rows - 1)) / rows))
          // Short cards put the icon beside the label and value.
          readonly property bool sideways: cellHeight < Style.space(50)

          Grid {
            anchors.centerIn: parent
            columns: detailsPanel.columns
            spacing: detailsPanel.gap

            Repeater {
              model: detailsPanel.stats

              Rectangle {
                id: statCard
                required property var modelData
                width: detailsPanel.cellWidth
                height: detailsPanel.cellHeight
                radius: Style.space(7)
                color: root.cardColor

                Text {
                  id: statIcon
                  x: detailsPanel.sideways ? Style.space(6) : 0
                  y: detailsPanel.sideways ? (parent.height - height) / 2 : statText.y - height - Style.space(2)
                  width: detailsPanel.sideways ? Style.space(18) : parent.width
                  height: Style.space(16)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  text: statCard.modelData.icon || ""
                  color: root.foreground
                  opacity: 0.7
                  rotation: Number(statCard.modelData.turn) || 0
                  font.family: root.fontFamily
                  font.pixelSize: root.glyphSize(Style.space(13))
                }

                Column {
                  id: statText
                  x: detailsPanel.sideways ? statIcon.x + statIcon.width + Style.space(4) : Style.space(3)
                  y: detailsPanel.sideways
                    ? (parent.height - height) / 2
                    : (parent.height - height + statIcon.height + Style.space(2)) / 2
                  width: detailsPanel.sideways ? parent.width - x - Style.space(4) : parent.width - Style.space(6)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    horizontalAlignment: detailsPanel.sideways ? Text.AlignLeft : Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: statCard.modelData.label
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: root.tinyPx
                    font.weight: Font.Medium
                    font.letterSpacing: 0.6
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: detailsPanel.sideways ? Text.AlignLeft : Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: statCard.modelData.value
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption + 1
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }

        // WEEK: a column per day with a bar from its low to its high.
        Item {
          id: weekPanel
          readonly property bool shown: root.currentPanel === "week"
          anchors.fill: parent
          opacity: weekPanel.shown ? 1 : 0
          visible: opacity > 0.01
          transform: Translate { x: (weekPanel.shown ? 1 : -1) * (1 - weekPanel.opacity) * Style.space(10) }
          Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          readonly property var days: root.forecastDays()
          readonly property var range: Weather.temperatureSpan(days)
          readonly property real column: width / Math.max(1, days.length)
          readonly property int dayHeight: root.tinyPx + Style.space(4)
          readonly property int glyphHeight: Style.space(root.compact ? 18 : 22)
          // A compact tile has no room for rain chances and still a readable bar.
          readonly property int rainHeight: root.compact ? 0 : root.tinyPx + Style.space(3)
          readonly property int valueHeight: Style.font.caption + Style.space(3)
          readonly property int barHeight: Math.max(Style.space(12), Math.min(Math.max(Style.space(46), height * 0.4),
            height - dayHeight - glyphHeight - rainHeight - valueHeight * 2 - Style.space(6)))
          readonly property int stackHeight: dayHeight + glyphHeight + rainHeight + valueHeight * 2 + barHeight + Style.space(4)
          readonly property int stackTop: Math.max(0, Math.round((height - stackHeight) / 2))

          Repeater {
            model: weekPanel.days

            Item {
              id: dayColumn
              required property var modelData
              required property int index
              readonly property real highAt: Weather.spanOffset(weekPanel.range, dayColumn.modelData.high)
              readonly property real lowAt: Weather.spanOffset(weekPanel.range, dayColumn.modelData.low)
              x: index * weekPanel.column
              width: weekPanel.column
              height: weekPanel.height

              Column {
                y: weekPanel.stackTop
                width: parent.width

                Text {
                  width: parent.width
                  height: weekPanel.dayHeight
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: dayColumn.modelData.label === "TOMORROW" ? "TOM" : dayColumn.modelData.label
                  color: root.foreground
                  opacity: dayColumn.index === 0 ? 0.85 : 0.5
                  font.family: root.fontFamily
                  font.pixelSize: root.tinyPx
                  font.weight: dayColumn.index === 0 ? Font.DemiBold : Font.Medium
                  font.letterSpacing: 0.3
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  height: weekPanel.glyphHeight
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  text: dayColumn.modelData.glyph
                  color: root.foreground
                  opacity: 0.9
                  font.family: root.fontFamily
                  font.pixelSize: root.glyphSize(Style.space(root.compact ? 15 : 17))
                }

                Text {
                  visible: weekPanel.rainHeight > 0
                  width: parent.width
                  height: weekPanel.rainHeight
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: dayColumn.modelData.precipProbability >= 20 ? Math.round(dayColumn.modelData.precipProbability) + "%" : ""
                  color: root.rainColor
                  font.family: root.fontFamily
                  font.pixelSize: root.tinyPx
                  font.weight: Font.Medium
                }

                Text {
                  width: parent.width
                  height: weekPanel.valueHeight
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: Weather.temperature(dayColumn.modelData.high, root.units)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption)
                  font.weight: Font.DemiBold
                  font.features: ({ "tnum": 1 })
                }

                Item {
                  width: parent.width
                  height: weekPanel.barHeight + Style.space(4)

                  Rectangle {
                    id: track
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Style.space(2)
                    width: Style.space(5)
                    height: weekPanel.barHeight
                    radius: width / 2
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                    Rectangle {
                      width: parent.width
                      y: dayColumn.highAt * parent.height
                      height: Math.max(width, (dayColumn.lowAt - dayColumn.highAt) * parent.height)
                      radius: width / 2
                      gradient: Gradient {
                        GradientStop { position: 0; color: Weather.temperatureColor(dayColumn.modelData.high) }
                        GradientStop { position: 1; color: Weather.temperatureColor(dayColumn.modelData.low) }
                      }
                    }

                    // Today: where it is now.
                    Rectangle {
                      visible: dayColumn.index === 0 && root.current !== null
                      readonly property real at: Weather.spanOffset(weekPanel.range, root.current ? root.current.temperature : null)
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: parent.width + Style.space(3)
                      height: width
                      radius: width / 2
                      y: Math.max(0, Math.min(parent.height - height, at * parent.height - height / 2))
                      color: root.foreground
                      border.width: Style.space(2)
                      border.color: Qt.rgba(0, 0, 0, 0.35)
                    }
                  }
                }

                Text {
                  width: parent.width
                  height: weekPanel.valueHeight
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignBottom
                  textFormat: Text.PlainText
                  text: Weather.temperature(dayColumn.modelData.low, root.units)
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(9, Style.font.caption)
                  font.weight: Font.Medium
                  font.features: ({ "tnum": 1 })
                }
              }
            }
          }
        }

        // RADAR: the last hour of RainViewer frames over Esri's gray map.
        Item {
          id: radarPanel
          readonly property bool shown: root.currentPanel === "radar"
          anchors.fill: parent
          opacity: radarPanel.shown ? 1 : 0
          visible: opacity > 0.01
          transform: Translate { x: (radarPanel.shown ? 1 : -1) * (1 - radarPanel.opacity) * Style.space(10) }
          Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          readonly property bool ready: root.radar !== null && root.radar.ok === true
          readonly property var placements: radarPanel.ready ? Weather.radarTiles(root.radar, width, height) : []
          readonly property var frame: root.radarFrames.length ? root.radarFrames[root.shownFrame] : null
          readonly property bool darkMap: !root.radar || root.radar.style !== "light"
          readonly property color inkColor: radarPanel.darkMap ? "#f2f2f2" : "#1d1d1d"
          readonly property color chipColor: radarPanel.darkMap ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(1, 1, 1, 0.65)

          Rectangle {
            id: radarMask
            anchors.fill: parent
            radius: Style.space(8)
            visible: false
            layer.enabled: true
          }

          Rectangle {
            anchors.fill: parent
            radius: Style.space(8)
            color: root.cardColor
            visible: !radarPanel.ready
          }

          Item {
            id: radarMap
            anchors.fill: parent
            visible: radarPanel.ready
            layer.enabled: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: radarMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1
            }

            Repeater {
              model: radarPanel.placements

              Item {
                id: mapTile
                required property var modelData
                readonly property int cell: mapTile.modelData.index
                x: mapTile.modelData.x
                y: mapTile.modelData.y
                width: root.radar.tileSize || 256
                height: width

                Image {
                  anchors.fill: parent
                  source: root.radar.base[mapTile.cell] ? "file://" + root.radar.base[mapTile.cell] : ""
                  asynchronous: false
                  smooth: true
                }

                Image {
                  anchors.fill: parent
                  opacity: 0.85
                  source: radarPanel.frame && radarPanel.frame.tiles[mapTile.cell] ? "file://" + radarPanel.frame.tiles[mapTile.cell] : ""
                  asynchronous: false
                  smooth: true
                }

                Image {
                  anchors.fill: parent
                  opacity: 0.9
                  source: root.radar.labels[mapTile.cell] ? "file://" + root.radar.labels[mapTile.cell] : ""
                  asynchronous: false
                  smooth: true
                }
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              height: Style.space(2)
              width: parent.width * (root.shownFrame + 1) / Math.max(1, root.radarFrames.length)
              color: Color.accent
              opacity: 0.8
              Behavior on width { NumberAnimation { duration: 200 } }
            }
          }

          // The forecast location.
          Item {
            anchors.centerIn: parent
            visible: radarPanel.ready

            Rectangle {
              id: pulse
              anchors.centerIn: parent
              width: Style.space(22)
              height: width
              radius: width / 2
              color: "transparent"
              border.width: 1.5
              border.color: Color.accent
              opacity: 0
              ParallelAnimation {
                running: radarPanel.shown && root.visible
                loops: Animation.Infinite
                NumberAnimation { target: pulse; property: "scale"; from: 0.3; to: 1; duration: 1600; easing.type: Easing.OutCubic }
                NumberAnimation { target: pulse; property: "opacity"; from: 0.9; to: 0; duration: 1600; easing.type: Easing.OutCubic }
              }
            }

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(14)
              height: width
              radius: width / 2
              color: radarPanel.chipColor
            }

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(9)
              height: width
              radius: width / 2
              color: Color.accent
              border.width: Style.space(2)
              border.color: radarPanel.inkColor
            }
          }

          Row {
            visible: radarPanel.ready && radarPanel.frame !== null
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Style.space(5)
            spacing: Style.space(4)

            Rectangle {
              width: frameText.implicitWidth + Style.space(10)
              height: frameText.implicitHeight + Style.space(4)
              radius: height / 2
              color: radarPanel.chipColor

              Text {
                id: frameText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: radarPanel.frame ? Weather.frameAge(radarPanel.frame.time, Date.now()) : ""
                color: radarPanel.inkColor
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
              }
            }

            // The closest rain in the newest frame, or none nearby.
            Rectangle {
              visible: root.radar !== null && root.radar.nearest !== undefined
              width: dryText.implicitWidth + Style.space(10)
              height: dryText.implicitHeight + Style.space(4)
              radius: height / 2
              color: radarPanel.chipColor

              Text {
                id: dryText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: Weather.nearestRain(root.radar ? root.radar.nearest : null, root.units, root.snowing)
                color: radarPanel.inkColor
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
              }
            }
          }

          Rectangle {
            visible: radarPanel.ready
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Style.space(5)
            anchors.bottomMargin: Style.space(5)
            width: creditText.implicitWidth + Style.space(8)
            height: creditText.implicitHeight + Style.space(2)
            radius: height / 2
            color: radarPanel.chipColor

            Text {
              id: creditText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(root.radar && root.radar.credit || "Esri · RainViewer")
              color: radarPanel.inkColor
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Math.max(7, root.tinyPx - 1)
            }
          }

          Text {
            visible: !radarPanel.ready
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.radar && root.radar.error ? String(root.radar.error) : "Loading radar…"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // AIR QUALITY: US AQI on its band scale, and the main pollutants.
        Item {
          id: airPanel
          readonly property bool shown: root.currentPanel === "air"
          anchors.fill: parent
          opacity: airPanel.shown ? 1 : 0
          visible: opacity > 0.01
          transform: Translate { x: (airPanel.shown ? 1 : -1) * (1 - airPanel.opacity) * Style.space(10) }
          Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          readonly property var band: root.air ? Weather.aqiBand(root.air.usAqi) : null
          readonly property var pollen: root.air ? Weather.topPollen(root.air.pollen) : null
          readonly property var trend: root.air && root.air.hourly ? root.air.hourly : []
          readonly property real trendPeak: Math.max(50, Math.max.apply(Math, airPanel.trend.length ? airPanel.trend : [0]))
          readonly property var cells: {
            var air = root.air || {}
            var list = [
              { label: "PM2.5", value: Weather.concentration(air.pm25), unit: "µg" },
              { label: "PM10", value: Weather.concentration(air.pm10), unit: "µg" },
              { label: "O₃", value: Weather.concentration(air.ozone), unit: "µg" }
            ]
            if (airPanel.pollen) {
              var name = airPanel.pollen.name
              list.push({ label: name.toUpperCase(), value: airPanel.pollen.level, unit: "" })
            } else {
              list.push({ label: "NO₂", value: Weather.concentration(air.no2), unit: "µg" })
            }
            return list
          }

          Column {
            visible: airPanel.band !== null
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(7)

            Item {
              width: parent.width
              height: aqiNumber.implicitHeight

              Text {
                id: aqiNumber
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.air ? String(Math.round(Number(root.air.usAqi))) : ""
                color: airPanel.band ? airPanel.band.color : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.round(root.heroPx * 0.62)
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
              }

              Column {
                anchors.left: aqiNumber.right
                anchors.leftMargin: Style.space(10)
                anchors.right: trendBars.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: airPanel.band ? airPanel.band.label : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "US AQI"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: root.tinyPx
                  font.letterSpacing: 0.6
                  elide: Text.ElideRight
                }
              }

              // The next 12 hours, one bar each.
              Row {
                id: trendBars
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
                spacing: Style.space(2)
                visible: airPanel.trend.length > 1 && !root.compact
                width: visible ? implicitWidth : 0

                Repeater {
                  model: airPanel.trend

                  Rectangle {
                    required property var modelData
                    anchors.bottom: parent.bottom
                    width: Style.space(3)
                    height: Style.space(3) + Number(modelData) / airPanel.trendPeak * Style.space(16)
                    radius: width / 2
                    color: Weather.aqiBand(modelData) ? Weather.aqiBand(modelData).color : root.foreground
                    opacity: 0.75
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: Style.space(12)

              Row {
                id: aqiScale
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: 6

                  Rectangle {
                    required property int index
                    width: (aqiScale.width - aqiScale.spacing * 5) / 6
                    height: Style.space(4)
                    radius: height / 2
                    color: ["#4cc36b", "#e3c440", "#f08c3a", "#e5534b", "#a05cc0", "#8c2a3c"][index]
                    opacity: airPanel.band && airPanel.band.index === index ? 1 : 0.35
                  }
                }
              }

              Rectangle {
                width: Style.space(11)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(parent.width - width, Weather.aqiPosition(root.air ? root.air.usAqi : 0) * parent.width - width / 2))
                color: airPanel.band ? airPanel.band.color : root.foreground
                border.width: Style.space(2)
                border.color: root.foreground
              }
            }

            Row {
              id: pollutants
              width: parent.width

              Repeater {
                model: airPanel.cells

                Column {
                  required property var modelData
                  width: pollutants.width / Math.max(1, airPanel.cells.length)
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: root.tinyPx
                    font.weight: Font.Medium
                    font.letterSpacing: 0.4
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: modelData.unit ? modelData.value + " " + modelData.unit : modelData.value
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          Text {
            visible: airPanel.band === null
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.sample && root.sample.cached ? "Loading air quality…" : "Air quality unavailable"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // SUN & MOON: the sun's arc from sunrise to sunset, and tonight's moon.
        Item {
          id: sunPanel
          readonly property bool shown: root.currentPanel === "sun"
          anchors.fill: parent
          opacity: sunPanel.shown ? 1 : 0
          visible: opacity > 0.01
          transform: Translate { x: (sunPanel.shown ? 1 : -1) * (1 - sunPanel.opacity) * Style.space(10) }
          Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          readonly property var sun: Weather.sunState(root.current ? root.current.time : "", root.daily[0] || null, root.daily[1] || null)
          // After sunset the times below are tomorrow's, matching the countdown.
          readonly property int dayIndex: !sunPanel.sun.day && sunPanel.sun.progress >= 1 && root.daily.length > 1 ? 1 : 0
          readonly property var today: root.daily[sunPanel.dayIndex] || null
          readonly property var tomorrow: root.daily[sunPanel.dayIndex + 1] || null
          readonly property var moon: Weather.moonPhase(root.sampledAt)
          readonly property int footHeight: Style.font.caption + root.tinyPx + Style.space(5)
          readonly property real arcLeft: Style.space(18)
          readonly property real arcRight: width - Style.space(18)
          readonly property real horizon: height - footHeight - Style.space(3)
          readonly property real apex: Style.space(10)
          onSunChanged: sunArc.requestPaint()

          function arcPoint(t) {
            return {
              x: sunPanel.arcLeft + (sunPanel.arcRight - sunPanel.arcLeft) * t,
              y: sunPanel.horizon - (sunPanel.horizon - sunPanel.apex) * Math.sin(Math.PI * t)
            }
          }

          Canvas {
            id: sunArc
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              if (width < 10 || height < 10) return
              var fg = root.foreground
              var warm = root.sunColor
              var sun = sunPanel.sun

              ctx.beginPath()
              ctx.moveTo(0, sunPanel.horizon)
              ctx.lineTo(width, sunPanel.horizon)
              ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.18)
              ctx.lineWidth = 1
              ctx.stroke()

              // The whole day's path, dotted.
              var steps = 34
              for (var i = 0; i <= steps; i++) {
                var dot = sunPanel.arcPoint(i / steps)
                ctx.beginPath()
                ctx.arc(dot.x, dot.y, 1, 0, Math.PI * 2)
                ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.3)
                ctx.fill()
              }

              if (!sun.day) return
              // The part already walked, solid, with daylight under it.
              var start = sunPanel.arcPoint(0)
              var here = sunPanel.arcPoint(sun.progress)
              var glow = ctx.createLinearGradient(0, sunPanel.apex, 0, sunPanel.horizon)
              glow.addColorStop(0, Qt.rgba(warm.r, warm.g, warm.b, 0.16))
              glow.addColorStop(1, Qt.rgba(warm.r, warm.g, warm.b, 0))
              ctx.beginPath()
              ctx.moveTo(start.x, sunPanel.horizon)
              for (var j = 0; j <= 40; j++) {
                var p = sunPanel.arcPoint(sun.progress * j / 40)
                ctx.lineTo(p.x, p.y)
              }
              ctx.lineTo(here.x, sunPanel.horizon)
              ctx.closePath()
              ctx.fillStyle = glow
              ctx.fill()

              ctx.beginPath()
              for (var k = 0; k <= 40; k++) {
                var q = sunPanel.arcPoint(sun.progress * k / 40)
                if (k === 0) ctx.moveTo(q.x, q.y)
                else ctx.lineTo(q.x, q.y)
              }
              ctx.strokeStyle = Qt.rgba(warm.r, warm.g, warm.b, 0.85)
              ctx.lineWidth = 1.6
              ctx.stroke()

              var halo = ctx.createRadialGradient(here.x, here.y, 0, here.x, here.y, 12)
              halo.addColorStop(0, Qt.rgba(warm.r, warm.g, warm.b, 0.55))
              halo.addColorStop(1, Qt.rgba(warm.r, warm.g, warm.b, 0))
              ctx.fillStyle = halo
              ctx.fillRect(here.x - 12, here.y - 12, 24, 24)
              ctx.beginPath()
              ctx.arc(here.x, here.y, 4.5, 0, Math.PI * 2)
              ctx.fillStyle = warm
              ctx.fill()
            }
          }

          // By day the countdown sits under the arc. At night the moon takes
          // the middle, with its phase and the countdown below it.
          Column {
            width: parent.width
            y: sunPanel.sun.day
              ? sunPanel.horizon - (sunPanel.horizon - sunPanel.apex) * (root.compact ? 0.3 : 0.42) - countdown.implicitHeight / 2
              : sunPanel.apex + (sunPanel.horizon - sunPanel.apex - implicitHeight) / 2 + Style.space(4)
            spacing: Style.space(2)

            Text {
              visible: !sunPanel.sun.day
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: sunPanel.moon.glyph
              color: root.foreground
              opacity: 0.9
              font.family: root.fontFamily
              font.pixelSize: root.glyphSize(Style.space(22))
            }

            Text {
              visible: !sunPanel.sun.day
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: sunPanel.moon.name + " · " + sunPanel.moon.illumination + "%"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: root.tinyPx
            }

            Text {
              id: countdown
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: isFinite(sunPanel.sun.until) ? sunPanel.sun.next + " in " + Weather.duration(sunPanel.sun.until) : ""
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
            }
          }

          // The moon sits in the top corner away from the sun.
          Row {
            id: moonCorner
            readonly property bool onLeft: sunPanel.sun.progress > 0.5
            visible: sunPanel.sun.day
            x: moonCorner.onLeft ? 0 : parent.width - width
            anchors.top: parent.top
            spacing: Style.space(5)
            layoutDirection: moonCorner.onLeft ? Qt.RightToLeft : Qt.LeftToRight

            Column {
              visible: !root.compact
              anchors.verticalCenter: parent.verticalCenter

              Text {
                x: moonCorner.onLeft ? 0 : parent.width - width
                textFormat: Text.PlainText
                text: sunPanel.moon.name
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
              }

              Text {
                x: moonCorner.onLeft ? 0 : parent.width - width
                textFormat: Text.PlainText
                text: sunPanel.moon.illumination + "% lit"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: sunPanel.moon.glyph
              color: root.foreground
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: root.glyphSize(Style.space(15))
            }
          }

          Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: sunPanel.footHeight

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: ""
                color: root.sunColor
                font.family: root.fontFamily
                font.pixelSize: root.glyphSize(Style.space(13))
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Weather.sunClock(sunPanel.today ? sunPanel.today.sunrise : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }

            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.compact

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: sunPanel.today ? Weather.duration(Number(sunPanel.today.daylight) / 60) : ""
                color: root.foreground
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: {
                  if (sunPanel.dayIndex > 0) return "tomorrow"
                  var change = Weather.daylightChange(sunPanel.today ? sunPanel.today.daylight : 0, sunPanel.tomorrow ? sunPanel.tomorrow.daylight : 0)
                  return change ? change + " tomorrow" : "daylight"
                }
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: root.tinyPx
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Weather.sunClock(sunPanel.today ? sunPanel.today.sunset : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: ""
                color: root.sunColor
                font.family: root.fontFamily
                font.pixelSize: root.glyphSize(Style.space(13))
              }
            }
          }
        }
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - Style.space(36)
    spacing: Style.space(7)
    visible: root.current === null

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.failed ? "" : "󰖐"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.glyphSize(root.glyphPx * 0.8)
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.failed ? "Weather unavailable" : "Finding your weather…"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.failed
        ? ((root.sample && root.sample.error) ? String(root.sample.error) : "Check the network, then choose a city in settings.")
        : (root.configuredLocation
            ? ("Loading " + String(root.configuredLocation.name || "saved location") + "…")
            : (root.settled ? "Using an approximate location…" : "Preparing forecast…"))
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Component.onCompleted: {
    if (root.configuredLocation) root.readDiskCache()
    root.scheduleSettle()
  }
  onVisibleChanged: {
    if (visible) {
      root.panelIndex = 0
      root.panelPaused = false
      root.restartDwell()
      if (root.haveWeather && root.lastFetchedKey === root.locationKey) {
        root.settled = true
        poll.restart()
        root.refresh("live")
      } else {
        root.scheduleSettle()
      }
    } else {
      settle.stop()
      followUp.stop()
      poll.stop()
    }
  }
  onConfiguredLocationChanged: {
    var nextKey = root.locationKey
    if (nextKey === root.lastSeenLocationKey) return
    root.lastSeenLocationKey = nextKey
    if (!root.settled) {
      // Binding just delivered settings; wait for settle debounce instead of racing.
      root.scheduleSettle()
      return
    }
    if (!root.configuredLocation) root.resolvedLocation = null
    root.sample = ({})
    root.haveWeather = false
    root.stale = false
    root.loaded = false
    root.displayedTemperature = 0
    root.lastFetchedKey = ""
    var painted = root.readDiskCache()
    if (probe.running) {
      probe.again = true
      probe.pendingMode = painted ? "live" : "cache-first"
    } else if (root.visible) {
      if (painted) root.queueFollowUp("live")
      else root.refresh("cache-first")
    }
  }
  onUnitsChanged: {
    // API payload stays metric; convert locally without wiping or refetching.
    root.syncDisplayedTemperature()
  }
  onAirEnabledChanged: {
    // Turned back on: fetch it now instead of at the next poll.
    if (root.airEnabled && !root.air && root.haveWeather && root.visible) root.refresh("live")
  }
  onPanelIndexChanged: root.restartDwell()
  onRotatingChanged: root.restartDwell()
  onPanelsChanged: {
    if (root.panelIndex >= root.panels.length) root.panelIndex = 0
  }
  onCurrentPanelChanged: {
    // The radar opens on its newest frame.
    if (root.currentPanel === "radar") root.radarFrame = Math.max(0, root.radarFrames.length - 1)
  }
  onForegroundChanged: {
    hoursCurve.requestPaint()
    sunArc.requestPaint()
  }
  onSkyKindChanged: root.repaintAtmosphere()
  onSkyStrengthChanged: root.repaintAtmosphere()
  onPhaseChanged: atmosphere.requestPaint()
}
