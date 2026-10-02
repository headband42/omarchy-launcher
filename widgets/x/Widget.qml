import QtQuick
import Quickshell.Io
import qs.Commons
import "../_kit"
import "../_kit/kit.js" as Kit
import "x.js" as X

// Today's News with a signed-in session, guest trends without one. Each
// headline wraps across the full width, and the list scrolls once it runs past
// the tile. A row opens that story on x.com; the header and margins launch
// Opens.
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

  readonly property var options: X.normalizedSettings(root.tile && root.tile.settings)
  readonly property var headlines: X.headlinesOf(root.sample)
  readonly property bool fresh: root.loaded && root.sample.ok === true && !root.sample.stale
  readonly property string badgeText: X.notificationLabel(root.sample && root.sample.notifications)
  readonly property string statusText: {
    if (!root.loaded) return "Loading…"
    if (root.sample && root.sample.ok === false)
      return String(root.sample.error || "Unavailable")
    return "No headlines"
  }
  // The hover tint reaches this far past the text on each side, so the text
  // lines up with the header while the tint still has room to breathe.
  readonly property int rowInset: Style.space(4)

  function applyPayload(parsed) {
    if (!parsed || typeof parsed !== "object") return
    root.sample = parsed
    root.loaded = true
    root.haveHeadlines = !!(parsed.ok && parsed.headlines && parsed.headlines.length)
    var poll = Number(parsed.pollMs)
    if (isFinite(poll) && poll > 0) pollTimer.interval = Math.max(60000, poll)
  }

  function buildArgs(mode) {
    var args = ["/usr/bin/python3", "-u", Kit.localPath(Qt.resolvedUrl("sample.py"))]
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
    if (row && row.url && root.host && root.host.openUrl) root.host.openUrl(String(row.url))
    else if (root.host && root.host.launchDefault) root.host.launchDefault()
  }

  Process {
    id: probe
    property bool again: false
    property string pendingMode: ""
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try {
        root.applyPayload(JSON.parse(probeOut.text || "{}"))
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
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      width: content.width - (badge.visible ? badge.width + Style.space(8) : 0)
      title: X.headerTitle(root.sample)
      trailing: X.placeCaption(root.sample, root.options)
      dotColor: root.fresh ? Color.accent : root.foreground
      dotOpacity: root.fresh ? 1 : 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // Unread notifications. It opens the notifications page, not the
    // headline under it.
    Rectangle {
      id: badge
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      visible: root.badgeText !== ""
      width: Math.max(height, badgeLabel.implicitWidth + Style.space(10))
      height: Style.space(16)
      radius: height / 2
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, badgeMouse.containsMouse ? 0.4 : 0.25)

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
        id: badgeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (root.host && root.host.openUrl) root.host.openUrl("https://x.com/notifications")
        }
      }
    }

    // A ListView so a long headline gets every line it needs and the rest
    // scroll. `interactive` is bound to the overflow: with nothing to scroll
    // the list must not swallow the wheel from the launcher around it.
    ListView {
      id: list
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: signIn.visible ? signIn.top : parent.bottom
      anchors.bottomMargin: signIn.visible ? Style.space(4) : 0
      anchors.leftMargin: -root.rowInset
      anchors.rightMargin: -root.rowInset
      clip: true
      model: root.headlines
      boundsBehavior: Flickable.StopAtBounds
      interactive: list.contentHeight > list.height + 1

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property string meta: X.headlineMeta(row.modelData)

        width: list.width
        height: stack.implicitHeight + Style.space(12)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: root.foreground
          opacity: rowMouse.containsMouse ? 0.08 : 0
        }

        // A hairline between stories, since a wrapped headline runs into the
        // next one without it.
        Rectangle {
          visible: row.index > 0 && !rowMouse.containsMouse
          x: root.rowInset
          width: row.width - root.rowInset * 2
          height: 1
          color: root.foreground
          opacity: 0.08
        }

        Column {
          id: stack
          x: root.rowInset
          width: row.width - root.rowInset * 2
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(row.modelData.title || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.1
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
          }

          Text {
            visible: row.meta !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: row.meta
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openHeadline(row.modelData)
        }
      }
    }

    // Where the list is scrolled to. It sits in the tile's margin so it never
    // covers the end of a line.
    Rectangle {
      visible: list.interactive
      anchors.left: list.right
      anchors.leftMargin: Style.space(2)
      width: Style.space(2)
      height: Math.max(Style.space(14), list.visibleArea.heightRatio * list.height)
      y: list.y + Math.min(list.height - height, list.visibleArea.yPosition * list.height)
      radius: width / 2
      color: root.foreground
      opacity: list.moving ? 0.5 : 0.2

      Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Text {
      visible: root.headlines.length === 0
      anchors.centerIn: list
      width: list.width - Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.statusText
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      id: signIn
      visible: root.headlines.length > 0 && X.signInHint(root.sample)
      anchors.bottom: parent.bottom
      width: parent.width
      textFormat: Text.PlainText
      text: "Guest trends · sign in for news"
      color: root.foreground
      opacity: 0.35
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
