import QtQuick
import Quickshell.Io
import qs.Commons
import "opencode.js" as Go

Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  property bool loaded: false
  property bool haveData: false

  // Panel settings. `hidden` is a comma list of block ids, so a tile can
  // show only the blocks that matter to the person looking at it.
  readonly property string hiddenBlocks: String((root.tile && root.tile.settings && root.tile.settings.hidden) || "")
  readonly property string resetStyle: String((root.tile && root.tile.settings && root.tile.settings.resetStyle) || "relative")
  readonly property bool showAmounts: !(root.tile && root.tile.settings && root.tile.settings.showAmounts === false)

  readonly property bool failed: root.loaded && !!root.sample && root.sample.ok === false
  readonly property var meters: Go.metersOf(root.sample, root.hiddenBlocks)
  readonly property bool compact: root.height < 240
  readonly property bool roomy: root.height >= 265
  readonly property int pollMs: {
    var n = Number(root.sample && root.sample.pollMs)
    if (!isFinite(n) || n < 30000) return 300000
    if (n > 900000) return 900000
    return Math.round(n)
  }
  readonly property string tileUrl: {
    // The launcher allowlists this exact prefix, so the guard here is the
    // same one. A click with nowhere to go would silently do nothing.
    var value = "https://opencode.ai/console"
    return value.indexOf("https://opencode.ai/") === 0 ? value : ""
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  // The theme's own accent warmed toward its own urgent color, so a bar reads
  // as filling up without inventing a color the theme does not have.
  function rampColor(fraction) {
    var from = Color.accent
    var to = Color.urgent
    var t = Math.max(0, Math.min(1, Number(fraction)))
    return Qt.rgba(from.r + (to.r - from.r) * t,
                   from.g + (to.g - from.g) * t,
                   from.b + (to.b - from.b) * t, 1)
  }

  function barColor(meter) {
    return root.rampColor(Go.toneFraction(Go.tone(meter)))
  }

  function refresh() {
    if (!root.visible) return
    if (probe.running) {
      probe.again = true
      return
    }
    probe.command = ["/usr/bin/python3", root.scriptPath("sample.py")]
    probe.running = true
  }

  Process {
    id: probe
    property bool again: false
    command: ["/usr/bin/python3", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      var parsed = null
      try { parsed = JSON.parse(probeOut.text || "") } catch (e) { parsed = null }
      if (parsed && parsed.ok) {
        root.sample = parsed
        root.haveData = true
      } else if (!root.haveData) {
        root.sample = parsed || {
          ok: false, plan: "", active: false, error: "Go usage unavailable",
          meters: [], currency: "USD"
        }
      }
      root.loaded = true
      if (probe.again) {
        probe.again = false
        Qt.callLater(root.refresh)
        return
      }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: root.pollMs
    onTriggered: root.refresh()
  }

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    visible: root.loaded && !root.failed && root.meters.length > 0

    // ------------------------------------------------------------- header
    Item {
      id: header
      width: parent.width
      height: Style.font.caption + Style.space(6)

      Text {
        id: plan
        anchors.left: parent.left
        anchors.right: statusText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Go.planLabel(root.sample)
        color: root.foreground
        opacity: 0.8
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        elide: Text.ElideRight
      }

      Row {
        id: statusText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Rectangle {
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          color: Go.statusTone(root.sample) === "calm" ? Color.accent
               : (Go.statusTone(root.sample) === "warm" ? root.rampColor(Go.toneFraction("warm")) : Color.muted)
          opacity: 0.85
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Go.statusText(root.sample)
          color: root.foreground
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 0.5
        }
      }
    }

    Text {
      id: renewal
      width: parent.width
      anchors.top: header.bottom
      anchors.topMargin: Style.space(2)
      textFormat: Text.PlainText
      text: Go.renewalLine(root.sample)
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Style.font.caption - 2)
      elide: Text.ElideRight
    }

    // ------------------------------------------------------------ the bars
    //
    // One row per block: the name, the bar, the percentage, and underneath
    // what was spent of what and when the block frees up.
    Column {
      id: rows
      width: parent.width
      height: Math.max(0, parent.height - header.height - renewal.height - Style.space(10))
      anchors.top: renewal.bottom
      anchors.topMargin: Style.space(8)
      spacing: Style.space(4)

      Repeater {
        model: root.meters

        Item {
          id: row
          required property var modelData
          required property int index
          width: rows.width
          height: rows.height / Math.max(1, root.meters.length)
          readonly property var meter: row.modelData

          // The headline percentage is the block closest to its ceiling, so a
          // glance at one corner tells you whether to worry.
          readonly property bool headline: {
            var worst = Go.headlinePercent(root.meters)
            return !root.compact && Go.percent(row.meter) === worst
          }

          Item {
            id: top
            width: parent.width
            height: Style.font.caption + Style.space(2)
            anchors.top: parent.top

            Text {
              id: name
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Go.label(row.meter)
              color: root.foreground
              opacity: row.headline ? 0.9 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.weight: Font.DemiBold
              font.letterSpacing: 0.6
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Go.percent(row.meter)
              color: root.barColor(row.meter)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }
          }

          // The track and the fill. The fill stops at the track's width even
          // when the block is over its limit, which the percentage shows.
          Rectangle {
            id: track
            width: parent.width
            height: Style.space(7)
            radius: Style.space(4)
            anchors.top: top.bottom
            anchors.topMargin: Style.space(3)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

            Rectangle {
              id: fillBar
              width: Math.max(0, Math.min(track.width, track.width * Go.fill(row.meter)))
              height: parent.height
              radius: parent.radius
              color: root.barColor(row.meter)

              Behavior on width {
                NumberAnimation { duration: 550; easing.type: Easing.OutCubic }
              }
            }
          }

          Text {
            id: detail
            width: parent.width
            visible: !root.compact
            anchors.top: track.bottom
            anchors.topMargin: Style.space(3)
            textFormat: Text.PlainText
            text: {
              if (!root.showAmounts) return Go.resetLine(row.meter, root.resetStyle)
              var money = Go.usedLine(row.meter, root.sample.currency)
              var reset = Go.resetLine(row.meter, root.resetStyle)
              if (money && reset) return money + "  ·  " + reset
              return money || reset
            }
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 2)
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // No console account, an expired sign-in, or a plan with no blocks. Each
  // says which, because the fix is different for each.
  Column {
    id: placeholder
    anchors.centerIn: parent
    width: parent.width - Style.space(36)
    spacing: Style.space(7)
    visible: !root.loaded || root.failed || root.meters.length < 1

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Go.emptyHeadline(root.sample)
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
      maximumLineCount: 5
      textFormat: Text.PlainText
      text: Go.emptyBody(root.sample)
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A click opens the console, where the same numbers live in full.
  MouseArea {
    anchors.fill: parent
    visible: root.loaded && !root.failed
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.host && root.host.openUrl) root.host.openUrl(root.tileUrl)
    }
  }

  Component.onCompleted: root.refresh()
  onVisibleChanged: if (visible) root.refresh()
}
