import QtQuick
import Quickshell.Io
import qs.Commons
import "x.js" as X

Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  property bool loaded: false
  property bool haveHeadlines: false
  property bool stale: false
  property int selectedIndex: 0

  readonly property var options: X.normalizedSettings(root.tile && root.tile.settings)
  readonly property var headlines: {
    var rows = (root.sample && root.sample.headlines) || []
    return rows && rows.length ? rows : []
  }
  readonly property string sourceLabel: String((root.sample && root.sample.sourceLabel) || "X")
  readonly property string placeName: {
    var place = root.sample && root.sample.place
    if (place && place.name) return String(place.name)
    return String(root.options.placeName || "Worldwide")
  }
  readonly property string badgeText: X.notificationLabel(root.sample && root.sample.notifications)
  readonly property bool showBadge: root.badgeText !== ""
  readonly property string statusHint: {
    if (!root.loaded) return "Loading…"
    if (root.sample && root.sample.ok === false)
      return String(root.sample.error || "Unavailable")
    if (root.stale) return "Cached"
    return ""
  }
  readonly property int rowPx: {
    var n = Math.max(1, root.headlines.length)
    var available = Math.max(Style.space(80), root.height - Style.space(52))
    var px = Math.floor(available / Math.min(n, root.options.maxHeadlines))
    return Math.max(Style.space(18), Math.min(Style.space(28), px))
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function applyPayload(parsed) {
    if (!parsed || typeof parsed !== "object") return
    root.sample = parsed
    root.loaded = true
    root.haveHeadlines = !!(parsed.ok && parsed.headlines && parsed.headlines.length)
    root.stale = !!parsed.stale
    if (root.selectedIndex >= root.headlines.length) root.selectedIndex = 0
    var poll = Number(parsed.pollMs)
    if (isFinite(poll) && poll > 0) pollTimer.interval = Math.max(60000, poll)
  }

  function buildArgs(mode) {
    var args = ["/usr/bin/python3", "-u", root.scriptPath("sample.py")]
    args.push("--woeid", String(root.options.woeid))
    if (root.options.placeName) args.push("--place", String(root.options.placeName))
    args.push("--max", String(root.options.maxHeadlines))
    args.push("--cookies", X.effectiveCookiesPath(root.options.cookiesPath))
    if (mode === "cache-only") args.push("--cache-only")
    else if (mode === "cache-first") args.push("--cache-first")
    return args
  }

  function startProbe(mode) {
    if (probe.running) {
      probe.again = true
      probe.pendingMode = mode || "live"
      return
    }
    probe.pendingMode = ""
    probe.command = root.buildArgs(mode || "live")
    probe.running = true
  }

  function refresh(mode) {
    root.startProbe(mode || "live")
  }

  function openHeadline(row) {
    if (!row || !row.url) {
      if (root.host && root.host.launchDefault) root.host.launchDefault()
      return
    }
    if (root.host && root.host.openUrl) root.host.openUrl(String(row.url))
    else if (root.host && root.host.launchDefault) root.host.launchDefault()
  }

  function openExplore() {
    var url = "https://x.com/explore/tabs/news"
    if (root.host && root.host.openUrl) root.host.openUrl(url)
    else if (root.host && root.host.launchDefault) root.host.launchDefault()
  }

  Process {
    id: probe
    property bool again: false
    property string pendingMode: ""
    command: ["/usr/bin/python3", "-u", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try {
        var parsed = JSON.parse(probeOut.text || "{}")
        root.applyPayload(parsed)
      } catch (e) {
        if (!root.haveHeadlines) {
          root.loaded = true
          root.sample = { ok: false, error: "Bad X payload", headlines: [] }
        }
      }
      if (probe.again) {
        probe.again = false
        root.startProbe(probe.pendingMode || "live")
      } else if (root.visible) {
        pollTimer.restart()
      }
    }
  }

  Timer {
    id: pollTimer
    interval: 300000
    repeat: true
    running: root.visible
    onTriggered: root.refresh("live")
  }

  onVisibleChanged: {
    if (visible) root.refresh("cache-first")
  }

  onOptionsChanged: {
    if (root.visible) root.refresh("cache-first")
  }

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(10)

    Column {
      id: stack
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: Math.max(titleRow.implicitHeight, badgeBox.height)

        Row {
          id: titleRow
          anchors.left: parent.left
          anchors.right: badgeBox.left
          anchors.rightMargin: root.showBadge ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: "𝕏"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }

          Column {
            width: Math.max(Style.space(40), titleRow.width - Style.space(28))
            spacing: 0

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.sourceLabel.toUpperCase()
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: 1
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.placeName
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Rectangle {
          id: badgeBox
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.showBadge
          width: Math.max(Style.space(22), badgeLabel.implicitWidth + Style.space(10))
          height: Style.space(18)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

          Text {
            id: badgeLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.badgeText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.host && root.host.openUrl) root.host.openUrl("https://x.com/notifications")
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }

      Text {
        visible: root.statusHint !== "" && root.headlines.length === 0
        width: parent.width
        textFormat: Text.PlainText
        text: root.statusHint
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Column {
        width: parent.width
        spacing: Style.space(1)
        visible: root.headlines.length > 0

        Repeater {
          model: root.headlines

          Item {
            required property var modelData
            required property int index
            width: parent.width
            height: root.rowPx

            readonly property bool active: index === root.selectedIndex

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: parent.active
                     ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                     : "transparent"
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(2)
              anchors.rightMargin: Style.space(2)
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(index + 1)
                color: root.foreground
                opacity: 0.35
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.features: ({ "tnum": 1 })
                width: Style.space(14)
                horizontalAlignment: Text.AlignRight
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(Style.space(40), parent.width - Style.space(70))
                textFormat: Text.PlainText
                text: String(modelData.title || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: parent.parent.active ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: X.volumeLabel(modelData.volume) !== ""
                textFormat: Text.PlainText
                text: X.volumeLabel(modelData.volume)
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.features: ({ "tnum": 1 })
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = index
              onClicked: root.openHeadline(modelData)
            }
          }
        }
      }

      Text {
        visible: root.headlines.length > 0 && !!(root.sample && root.sample.newsBlocked)
        width: parent.width
        textFormat: Text.PlainText
        text: "Guest trends · News needs cookies"
        color: root.foreground
        opacity: 0.35
        font.family: root.fontFamily
        font.pixelSize: Math.max(10, Style.font.caption - 1)
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openExplore()
    }
  }
}
