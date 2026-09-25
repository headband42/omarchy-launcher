import QtQuick
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
  readonly property string locationKey: {
    var place = root.activeLocation || {}
    var latitude = place.latitude === undefined ? "" : place.latitude
    var longitude = place.longitude === undefined ? "" : place.longitude
    return String(latitude) + "," + String(longitude)
  }
  readonly property int code: root.current ? Math.round(Number(root.current.code)) : -1
  readonly property bool precipitating: root.code >= 51
  readonly property bool snowing: (root.code >= 71 && root.code <= 77) || root.code === 85 || root.code === 86
  readonly property bool compact: root.height < Style.space(230)
  readonly property bool roomy: root.height >= Style.space(240)
  readonly property int chartCount: Weather.hourlyCount(Math.max(0, root.width - Style.space(28)))
  readonly property var chartHours: {
    var count = Math.min(root.chartCount, root.hourly.length)
    if (count < 1) return []
    return root.hourly.slice(0, count)
  }
  readonly property bool failed: root.loaded && !root.haveWeather
  readonly property int heroPx: Math.max(Style.font.heading, Math.round(Math.min(root.width * 0.2, root.height * (root.compact ? 0.22 : 0.25))))
  readonly property int glyphPx: Math.max(Style.space(30), Math.round(root.heroPx * 0.9))
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
    if (currentTime && currentTime < sunset) return Weather.clock(sunset, true)
    var tomorrow = root.daily.length > 1 ? root.daily[1] : null
    return tomorrow && tomorrow.sunrise ? Weather.clock(tomorrow.sunrise, true) : Weather.clock(sunset, true)
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
    return Weather.dailyDays(root.daily, root.roomy ? 5 : 4)
  }

  function staleHint() {
    return root.stale ? "Showing last good reading" : "Live"
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
        if (!(root.haveWeather && root.lastFetchedKey === root.locationKey))
          root.refresh("cache-first")
        return
      }
      if (root.hasBoundTile() || root.settleAttempts >= 5) {
        root.settled = true
        root.settleAttempts = 0
        if (!(root.haveWeather && root.lastFetchedKey === root.locationKey))
          root.refresh("cache-first")
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

  NumberAnimation on phase {
    from: 0
    to: 1
    duration: 2600
    loops: Animation.Infinite
    running: root.visible && (root.precipitating || root.snowing)
  }

  Behavior on displayedTemperature {
    NumberAnimation { duration: 650; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(root.skyTop.r, root.skyTop.g, root.skyTop.b, 0.58) }
      GradientStop { position: 1; color: Qt.rgba(root.skyBottom.r, root.skyBottom.g, root.skyBottom.b, 0.2) }
    }
  }

  Canvas {
    id: atmosphere
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (width < 2 || height < 2) return
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
    anchors.margins: Style.space(14)
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
          visible: root.roomy
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
      height: root.compact ? Style.space(82) : Style.space(108)
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
          text: Weather.glyph(root.code, root.current ? root.current.isDay : true)
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
            visible: root.roomy
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

    Rectangle {
      id: chartCard
      width: parent.width
      height: root.compact ? Style.space(58) : Style.space(64)
      anchors.top: hero.bottom
      anchors.topMargin: Style.space(4)
      radius: Style.space(10)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.075)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
      visible: root.chartHours.length >= 3

      Text {
        id: chartTitle
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: Style.space(7)
        textFormat: Text.PlainText
        text: root.chartHours.length ? ("NEXT HOURS · RAIN " + root.rainChance()) : "NEXT HOURS"
        color: root.foreground
        opacity: 0.48
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 2)
        font.weight: Font.Medium
        font.letterSpacing: 0.7
      }

      Canvas {
        id: chart
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: chartTitle.bottom
        anchors.topMargin: Style.space(3)
        anchors.bottom: hourLabels.top
        anchors.margins: Style.space(8)
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var bars = Weather.precipBars(root.chartHours, width, height)
          for (var b = 0; b < bars.length; b++) {
            var bar = bars[b]
            if (bar.height < 0.5) continue
            var alpha = 0.12 + Math.min(0.38, bar.chance / 100 * 0.42)
            ctx.fillStyle = Qt.rgba(0.55, 0.78, 1, alpha)
            ctx.fillRect(bar.x, bar.y, bar.width, bar.height)
          }
          var points = Weather.chartPoints(root.chartHours, root.units, width, height)
          if (points.length < 2) return
          var fill = ctx.createLinearGradient(0, 0, 0, height)
          fill.addColorStop(0, Qt.rgba(1, 1, 1, 0.22))
          fill.addColorStop(1, Qt.rgba(1, 1, 1, 0))
          ctx.beginPath()
          ctx.moveTo(points[0].x, height)
          for (var i = 0; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y)
          ctx.lineTo(points[points.length - 1].x, height)
          ctx.closePath()
          ctx.fillStyle = fill
          ctx.fill()
          ctx.beginPath()
          ctx.moveTo(points[0].x, points[0].y)
          for (var j = 1; j < points.length; j++) ctx.lineTo(points[j].x, points[j].y)
          ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.92)
          ctx.lineWidth = Math.max(1.5, Math.min(2.5, width / 100))
          ctx.lineCap = "round"
          ctx.lineJoin = "round"
          ctx.stroke()
          ctx.font = Math.max(8, Math.round(Style.font.caption - 2)) + "px sans-serif"
          ctx.textAlign = "center"
          ctx.textBaseline = "bottom"
          for (var k = 0; k < points.length; k++) {
            ctx.beginPath()
            ctx.arc(points[k].x, points[k].y, 2.2, 0, Math.PI * 2)
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.9)
            ctx.fill()
            if (points[k].label) {
              ctx.fillStyle = Qt.rgba(1, 1, 1, 0.8)
              ctx.fillText(String(points[k].temperature) + "°", points[k].x, Math.max(10, points[k].y - 4))
            }
          }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
      }

      Row {
        id: hourLabels
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(5)
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)

        Repeater {
          model: root.chartHours

          Text {
            required property var modelData
            width: hourLabels.width / Math.max(1, root.chartHours.length)
            textFormat: Text.PlainText
            text: Weather.clock(modelData.time, true)
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 2)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }

    Grid {
      id: statsGrid
      width: parent.width
      anchors.top: chartCard.visible ? chartCard.bottom : hero.bottom
      anchors.topMargin: Style.space(6)
      columns: 4
      columnSpacing: 0
      rowSpacing: Style.space(4)
      visible: !root.compact || root.height >= Style.space(210)

      Repeater {
        model: {
          var rows = [
            { label: "RAIN", value: root.rainChance() },
            { label: "WIND", value: root.currentWind() + (root.currentDirection() ? " " + root.currentDirection() : "") },
            { label: "HUMIDITY", value: root.current ? Math.round(Number(root.current.humidity) || 0) + "%" : "—" },
            { label: "UV", value: root.uvLabel(root.current ? root.current.uv : null) }
          ]
          if (root.roomy) {
            rows.push({ label: "GUSTS", value: root.currentGust() })
            rows.push({ label: "PRESSURE", value: root.currentPressure() })
            if (root.height >= Style.space(280))
              rows.push({ label: "VIS", value: root.currentVisibility() })
          }
          return rows
        }

        Column {
          required property var modelData
          width: statsGrid.width / statsGrid.columns
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: modelData.label
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 2)
            font.weight: Font.Medium
            font.letterSpacing: 0.6
          }
          Text {
            width: parent.width - Style.space(4)
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

    Row {
      id: dailyStrip
      width: parent.width
      height: Style.space(40)
      anchors.top: statsGrid.visible ? statsGrid.bottom : (chartCard.visible ? chartCard.bottom : hero.bottom)
      anchors.topMargin: Style.space(4)
      visible: !root.compact && root.forecastDays().length >= 3
      spacing: 0

      Repeater {
        model: root.forecastDays()

        Column {
          required property var modelData
          width: dailyStrip.width / Math.max(1, root.forecastDays().length)
          spacing: Style.space(1)

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: modelData.label === "TODAY" ? "NOW" : (modelData.label === "TOMORROW" ? "TMW" : modelData.label)
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
            font.pixelSize: Style.space(14)
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

  Component.onCompleted: root.scheduleSettle()
  onVisibleChanged: {
    if (visible) {
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
    if (probe.running) {
      probe.again = true
      probe.pendingMode = "cache-first"
    } else if (root.visible) {
      root.refresh("cache-first")
    }
  }
  onUnitsChanged: {
    // API payload stays metric; convert locally without wiping or refetching.
    root.syncDisplayedTemperature()
    chart.requestPaint()
  }
  onSkyTopChanged: atmosphere.requestPaint()
  onPhaseChanged: atmosphere.requestPaint()
  onCurrentChanged: {
    chart.requestPaint()
    atmosphere.requestPaint()
  }
  onChartHoursChanged: {
    chart.requestPaint()
    atmosphere.requestPaint()
  }
  onCodeChanged: atmosphere.requestPaint()
}
