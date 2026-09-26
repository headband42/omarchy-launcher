import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "weather.js" as Weather

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
  readonly property string locationKey: {
    var place = root.activeLocation || {}
    var latitude = place.latitude === undefined ? "" : place.latitude
    var longitude = place.longitude === undefined ? "" : place.longitude
    return String(latitude) + "," + String(longitude)
  }
  readonly property int code: root.current ? Math.round(Number(root.current.code)) : -1
  readonly property bool precipitating: root.code >= 51
  readonly property bool snowing: (root.code >= 71 && root.code <= 77) || root.code === 85 || root.code === 86
  // At 1080p / scale 1 / text 11, tileSize is ~270–280px tall.
  // compact: denser hero; slightly fewer hour columns
  // roomy: denser DETAILS grid (gusts/pressure/vis)
  // Bottom half rotates HOURS → DETAILS → WEEK (~4s)
  readonly property bool compact: root.height < Style.space(250)
  // ~270-280px tiles stay mid (3x2 DETAILS); only taller tiles get 4x2.
  readonly property bool roomy: root.height >= Style.space(340)
  readonly property int chartCount: Weather.hourlyCount(Math.max(0, root.width - Style.space(28)))
  readonly property var chartHours: {
    var count = Math.min(root.chartCount, root.hourly.length)
    if (count < 1) return []
    return root.hourly.slice(0, count)
  }
  readonly property bool failed: root.loaded && !root.haveWeather
  readonly property int heroPx: Math.max(Style.font.heading, Math.round(Math.min(root.width * 0.2, root.height * (root.compact ? 0.22 : 0.25))))
  readonly property int glyphPx: Math.max(Style.space(30), Math.round(root.heroPx * 0.9))
  property int panelIndex: 0
  property bool panelPaused: false
  readonly property var panelTitles: ["HOURS", "DETAILS", "WEEK"]

  function selectPanel(index) {
    var next = Math.max(0, Math.min(2, Math.round(Number(index))))
    root.panelIndex = next
    root.panelPaused = true
    panelPause.restart()
  }

  // The old hourly Canvas chart was removed with the HOURS/DETAILS/WEEK carousel.
  // Do not call paint on that removed object — it ReferenceErrors and spams the shell log.
  function repaintAtmosphere() {
    if (atmosphere) atmosphere.requestPaint()
  }
  readonly property color skyTop: root.accentHex()
  readonly property color skyBottom: Qt.darker(root.skyTop, root.current && !root.current.isDay ? 1.7 : 1.35)

  property real displayedTemperature: 0

  function accentHex() {
    if (root.code === 0 || root.code === 1) return root.current && !root.current.isDay ? "#5269b7" : "#5da9d8"
    if (root.code === 2) return root.current && !root.current.isDay ? "#53619b" : "#6e8fc4"
    if (root.code === 3) return "#718092"
    if (root.code === 45 || root.code === 48) return "#77818d"
    if ((root.code >= 51 && root.code <= 67) || (root.code >= 80 && root.code <= 82)) return "#4d86b6"
    if ((root.code >= 71 && root.code <= 77) || root.code === 85 || root.code === 86) return "#77a9bd"
    if (root.code >= 95) return "#756cae"
    return "#6685aa"
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

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
    var args = ["/usr/bin/python3", "-u", root.scriptPath("sample.py")]
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
      { label: "RAIN", value: root.rainChance() },
      { label: "WIND", value: root.currentWind() + (root.currentDirection() ? " " + root.currentDirection() : "") },
      { label: "HUMIDITY", value: root.current ? Math.round(Number(root.current.humidity) || 0) + "%" : "—" },
      { label: "UV", value: root.uvLabel(root.current ? root.current.uv : null) },
      { label: "PRECIP", value: precip },
      { label: "GUSTS", value: root.currentGust() },
      { label: "PRESSURE", value: root.currentPressure() },
      { label: "VIS", value: root.currentVisibility() }
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
    if (root.compact) return 4
    return 3
  }

  function hourPrecip(row) {
    var chance = Number(row && row.precipProbability)
    if (!isFinite(chance) || chance < 5) return ""
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
    command: ["/usr/bin/python3", "-u", root.scriptPath("sample.py")]
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
    interval: 4000
    repeat: true
    running: root.visible && root.current !== null && !root.panelPaused
    onTriggered: root.panelIndex = (root.panelIndex + 1) % 3
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
    duration: 2600
    loops: Animation.Infinite
    running: root.visible && root.atmosphereEnabled && (root.precipitating || root.snowing)
  }

  Behavior on displayedTemperature {
    NumberAnimation { duration: 650; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    visible: root.atmosphereEnabled
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(root.skyTop.r, root.skyTop.g, root.skyTop.b, 0.58) }
      GradientStop { position: 1; color: Qt.rgba(root.skyBottom.r, root.skyBottom.g, root.skyBottom.b, 0.2) }
    }
  }

  Canvas {
    id: atmosphere
    anchors.fill: parent
    visible: root.atmosphereEnabled
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.atmosphereEnabled || width < 2 || height < 2) return
      var glow = ctx.createRadialGradient(width * 0.82, height * 0.16, 0, width * 0.82, height * 0.16, Math.max(width, height) * 0.72)
      glow.addColorStop(0, Qt.rgba(1, 1, 1, 0.2))
      glow.addColorStop(0.35, Qt.rgba(1, 1, 1, 0.05))
      glow.addColorStop(1, Qt.rgba(1, 1, 1, 0))
      ctx.fillStyle = glow
      ctx.fillRect(0, 0, width, height)
      if (!root.precipitating && !root.snowing) return
      var count = root.snowing ? 20 : 28
      for (var i = 0; i < count; i++) {
        var x = ((i * 47 + 19) % 101) / 100 * width
        var travel = (root.phase + (i * 0.137) % 1) % 1
        var y = (travel * (height + 30)) - 15
        if (root.snowing) {
          ctx.beginPath()
          ctx.arc(x + Math.sin(i * 1.7 + travel * 7) * 5, y, 1.2 + i % 2, 0, Math.PI * 2)
          ctx.fillStyle = Qt.rgba(1, 1, 1, 0.28)
          ctx.fill()
        } else {
          ctx.beginPath()
          ctx.moveTo(x, y)
          ctx.lineTo(x - 3, y + 10)
          ctx.strokeStyle = Qt.rgba(0.85, 0.94, 1, 0.24)
          ctx.lineWidth = 1
          ctx.stroke()
        }
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
          font.pixelSize: Math.max(8, Style.font.caption - 2)
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
      anchors.topMargin: Style.space(8)

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.glyphPx
          textFormat: Text.PlainText
          text: Weather.glyph(root.code, root.current ? root.current.isDay : 1)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.glyphPx
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
      anchors.topMargin: Style.space(6)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 0
      visible: root.current !== null

      Item {
        id: panelHeader
        width: parent.width
        height: Math.max(Style.font.caption + Style.space(2), Style.space(22))
        z: 2

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.panelTitles[root.panelIndex] || "HOURS"
          color: root.foreground
          opacity: 0.48
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.Medium
          font.letterSpacing: 0.7
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Repeater {
            model: 3
            // Large invisible hit target around each 5px page dot.
            Item {
              required property int index
              width: Style.space(22)
              height: Style.space(22)

              Rectangle {
                anchors.centerIn: parent
                width: 5
                height: 5
                radius: 2.5
                color: root.foreground
                opacity: index === root.panelIndex ? 0.75 : 0.22
              }

              MouseArea {
                anchors.fill: parent
                z: 3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse.accepted = true
                onClicked: {
                  mouse.accepted = true
                  root.selectPanel(index)
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
        anchors.topMargin: Style.space(4)
        anchors.bottom: parent.bottom
        clip: true

        // Panel 0 — HOURS: discrete columns (time / glyph / temp / precip%)
        Row {
          id: hoursPanel
          anchors.fill: parent
          spacing: 0
          opacity: root.panelIndex === 0 ? 1 : 0
          visible: opacity > 0.01
          Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

          Repeater {
            model: root.chartHours

            Column {
              required property var modelData
              width: hoursPanel.width / Math.max(1, root.chartHours.length)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Weather.clock(modelData.time, true)
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Weather.glyph(modelData.code, modelData.isDay)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(root.compact ? 14 : 16)
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Weather.temperature(modelData.temperature, root.units)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.max(10, Style.font.caption)
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.hourPrecip(modelData)
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                visible: text.length > 0
              }
            }
          }
        }

        // Panel 1 — DETAILS: denser stats grid (centered in carousel stage)
        Grid {
          id: detailsPanel
          width: Math.max(0, parent.width - Style.space(8))
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          columns: root.detailsColumns()
          columnSpacing: 0
          rowSpacing: Style.space(root.compact ? 4 : 8)
          opacity: root.panelIndex === 1 ? 1 : 0
          visible: opacity > 0.01
          Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

          Repeater {
            model: root.panelStats()

            Column {
              required property var modelData
              width: detailsPanel.width / Math.max(1, detailsPanel.columns)
              spacing: Style.space(2)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                font.weight: Font.Medium
                font.letterSpacing: 0.6
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.value
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
                elide: Text.ElideRight
              }
            }
          }
        }

        // Panel 2 — WEEK: multi-day strip (glyphs + H/L)
        Row {
          id: weekPanel
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(root.compact ? 52 : 64)
          spacing: 0
          opacity: root.panelIndex === 2 ? 1 : 0
          visible: opacity > 0.01
          Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

          Repeater {
            model: root.forecastDays()

            Column {
              required property var modelData
              width: weekPanel.width / Math.max(1, root.forecastDays().length)
              spacing: Style.space(2)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.label === "TODAY" ? "TODAY" : (modelData.label === "TOMORROW" ? "TOM" : modelData.label)
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                font.weight: Font.Medium
                font.letterSpacing: 0.3
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.glyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(root.compact ? 18 : 22)
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Weather.temperature(modelData.high, root.units).replace("°", "") + "/" + Weather.temperature(modelData.low, root.units).replace("°", "")
                color: root.foreground
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
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
      font.pixelSize: Math.round(root.glyphPx * 0.9)
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
  onSkyTopChanged: root.repaintAtmosphere()
  onPhaseChanged: root.repaintAtmosphere()
  onCurrentChanged: root.repaintAtmosphere()
  onChartHoursChanged: root.repaintAtmosphere()
  onCodeChanged: root.repaintAtmosphere()
}
