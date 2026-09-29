import QtQuick
import Quickshell.Io
import qs.Commons
import "herdr.js" as Herdr

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

  // The section the panel chose: "" for every workspace, "w1" for one
  // workspace, "w1:t2" for one tab.
  readonly property string sectionId: String((root.tile && root.tile.settings && root.tile.settings.sectionId) || "")
  readonly property bool busyOnly: !!(root.tile && root.tile.settings && root.tile.settings.busyOnly)

  readonly property string mode: root.haveData ? "list" : "empty"
  readonly property bool failed: root.loaded && !!root.sample && root.sample.ok === false
  readonly property var agents: Herdr.agentsOf(root.sample)
  readonly property int rowH: Herdr.rowHeight(root.height)
  readonly property bool twoLine: Herdr.twoLine(root.height)
  readonly property int capacity: Math.max(1, Math.floor(agentList.height / root.rowH))
  readonly property bool overflows: root.agents.length > root.capacity
  readonly property var counts: root.sample && root.sample.scopedCounts ? root.sample.scopedCounts : null
  readonly property var allCounts: root.sample && root.sample.counts ? root.sample.counts : null
  readonly property int pollMs: {
    var n = Number(root.sample && root.sample.pollMs)
    if (!isFinite(n) || n < 1000) return 10000
    if (n > 60000) return 60000
    return Math.round(n)
  }
  // The footer mirrors the list rather than keeping its own count, so the two
  // can never disagree about whether there is more to see.
  readonly property var window: Herdr.visibleWindow(agentList.contentY, root.rowH,
                                                   root.agents.length, root.capacity)

  // Which agent is at the top, so a poll that reorders the list does not throw
  // away the reader's place.
  property string scrollAnchor: ""

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function refresh() {
    if (!root.visible) return
    if (probe.running) {
      probe.again = true
      return
    }
    var args = ["/usr/bin/python3", root.scriptPath("sample.py")]
    if (root.sectionId.length > 0) args.push("--section", root.sectionId)
    if (root.busyOnly) args.push("--busy")
    probe.key = root.sectionId + (root.busyOnly ? "|busy" : "")
    probe.command = args
    probe.running = true
  }

  // A row click asks the launcher to move the session's focus to that agent.
  // The pane id is checked here, and again in the launcher, so a row cannot
  // name anything but a pane.
  function focusAgent(agent) {
    var pane = Herdr.paneId(agent)
    if (!pane) return
    if (root.host && root.host.focusAgent) root.host.focusAgent(pane)
  }

  function toneColor(tone) {
    if (tone === "urgent") return Color.urgent
    if (tone === "accent") return Color.accent
    if (tone === "quiet") return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.34)
  }

  function rememberScroll() {
    if (root.agents.length < 1) return
    var row = root.rowH
    var i = Math.floor(Math.max(0, agentList.contentY) / row)
    if (i < 0) i = 0
    if (i > root.agents.length - 1) i = root.agents.length - 1
    root.scrollAnchor = String((root.agents[i] && root.agents[i].paneId) || "")
  }

  function restoreScroll() {
    if (root.agents.length < 1) { agentList.contentY = 0; return }
    if (!root.scrollAnchor) { agentList.contentY = 0; return }
    for (var i = 0; i < root.agents.length; i++) {
      if (String((root.agents[i] && root.agents[i].paneId) || "") === root.scrollAnchor) {
        agentList.contentY = i * root.rowH
        return
      }
    }
    agentList.contentY = 0
  }

  Process {
    id: probe
    property bool again: false
    property string key: ""
    command: ["/usr/bin/python3", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      // The section changed while this was running. Drop the stale payload.
      if (probe.key !== root.sectionId + (root.busyOnly ? "|busy" : "")) {
        probe.again = false
        if (root.visible) Qt.callLater(root.refresh)
        return
      }
      var parsed = null
      try { parsed = JSON.parse(probeOut.text || "") } catch (e) { parsed = null }
      if (parsed && parsed.ok) {
        root.sample = parsed
        root.haveData = true
      } else if (!root.haveData) {
        root.sample = parsed || {
          ok: false, banner: "HERDR", error: "Herdr is not answering",
          agents: [], total: 0, counts: {}, sectionLabel: "All sections"
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

  // Margins, gaps and the header below follow the sysmon tile, so the two
  // read as the same kind of thing at a glance: 12 in from the edge, an 8
  // gap, and a rule above the footer.
  Column {
    id: chrome
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    // A ListView rather than a Column, so a session with more agents than fit
    // scrolls instead of clipping. `interactive` turns on both the wheel and
    // drag, and it is bound to the overflow on purpose: with nothing to scroll
    // the list must not swallow the wheel from the launcher around it.
    Item {
      id: listWrap
      width: parent.width
      height: parent.height - header.height - footer.height - parent.spacing * 2
      clip: true

      ListView {
        id: agentList
        anchors.fill: parent
        clip: true
        spacing: 0
        model: root.agents
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.overflows
        highlightMoveDuration: 0
        onContentYChanged: root.rememberScroll()

        delegate: Item {
          id: row
          required property int index
          required property var modelData
          width: agentList.width
          height: root.rowH

          readonly property var agent: row.modelData
          readonly property color tone: root.toneColor(Herdr.statusTone(Herdr.statusOf(row.agent)))

          // The status dot is the one thing that has to read at a glance, so it
          // keeps its own column and never competes with the title for width.
          Rectangle {
            id: dot
            width: 7
            height: 7
            radius: 3.5
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: row.tone

            SequentialAnimation on opacity {
              running: Herdr.isBusy(Herdr.statusOf(row.agent)) && !Herdr.isFocused(row.agent)
              loops: Animation.Infinite
              NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
              NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
              }
            }

          Rectangle {
            id: focusBar
            width: 2
            height: parent.height - Style.space(6)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: Herdr.isFocused(row.agent)
            color: root.foreground
            opacity: 0.5
            }

          Column {
            id: text
            anchors.left: dot.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            // Room kept for the chevron, so the title never runs under it.
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: Herdr.agentName(row.agent)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: Math.max(Style.space(40), Math.min(
                Math.round(text.width * 0.5),
                implicitWidth + Style.space(8)))
                }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Herdr.statusLabel(Herdr.statusOf(row.agent))
                color: row.tone
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                font.weight: Font.Medium
                font.letterSpacing: 0.5
                }
              }

            Text {
              width: parent.width
              visible: root.twoLine
              textFormat: Text.PlainText
              text: Herdr.agentTitle(row.agent)
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              }
            }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            visible: row.index < agentList.count - 1
            color: root.foreground
            opacity: 0.07
            }

          // A row is its own target. A click on it asks the launcher to move the
          // session's focus to that agent, which is the one action here that
          // changes something outside the launcher.
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: Herdr.isFocusable(row.agent)
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.focusAgent(row.agent)
            }

          // The affordance, so a row reads as a thing you can go to rather than
          // as a line of text.
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: rowMouse.enabled && (rowMouse.containsMouse || Herdr.isFocused(row.agent))
            textFormat: Text.PlainText
            text: "›"
            color: root.foreground
            opacity: rowMouse.containsMouse ? 0.8 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            }
          }
        }

      // A soft edge so a cut-off row reads as "there is more" rather than as a
      // rendering mistake.
      Rectangle {
        id: fade
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(12)
        visible: root.overflows
        gradient: Gradient {
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
        }
      }
    }

    // ------------------------------------------------------------- the chrome
    Item {
      id: header
      width: chrome.width
      height: Style.font.caption + 4

      // The dot says the state of the session, the way the sysmon tile's dot
      // says it is alive. It does not pulse: here the colour carries the
      // meaning, and a moving dot would be saying something else.
      Rectangle {
        id: sessionDot
        width: 6
        height: 6
        radius: 3
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.toneColor(Herdr.headlineTone(root.counts))
        opacity: root.failed || !root.haveData ? 0.3 : 0.9
        }

      Text {
        id: banner
        anchors.left: sessionDot.right
        anchors.leftMargin: Style.space(6)
        anchors.right: statusText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "HERDR"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
        }

      Text {
        id: statusText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Herdr.headline(root.counts)
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
        }
      }

    Item {
      id: footer
      width: chrome.width
      height: Style.space(26)

      Rectangle {
        id: footerRule
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

      Row {
        anchors.left: parent.left
        anchors.right: hintText.left
        anchors.rightMargin: Style.space(8)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Herdr.sectionLabel(root.sample)
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Math.max(Style.space(40), parent.width * 0.6))
          }

        // The count is scoped to the section, and the detail is the whole
        // session, so a narrowed tile still says what it left out.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.sample && root.sample.hidden > 0
          textFormat: Text.PlainText
          text: root.sample ? "+" + root.sample.hidden : ""
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.DemiBold
          }
        }

      Text {
        id: hintText
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        textFormat: Text.PlainText
        text: {
          var hint = Herdr.footerHint(root.window)
          if (hint) return hint
          return root.window.text
          }
        color: root.foreground
        opacity: root.overflows ? 0.6 : 0.35
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 2)
        font.features: ({ "tnum": 1 })
        }
      }
    }

  // Nothing to list: either Herdr is not answering, or this section has no
  // agents. Both say which.
  Column {
    id: placeholder
    anchors.centerIn: parent
    width: parent.width - Style.space(36)
    spacing: Style.space(7)
    visible: !root.loaded || root.failed || root.agents.length < 1

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Herdr.emptyHeadline(root.sample)
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
      maximumLineCount: 4
      textFormat: Text.PlainText
      text: Herdr.emptyBody(root.sample)
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Component.onCompleted: root.refresh()
  onVisibleChanged: if (visible) root.refresh()
  onSectionIdChanged: {
    root.sample = ({})
    root.haveData = false
    root.loaded = false
    root.scrollAnchor = ""
    if (root.visible) root.refresh()
  }
  onBusyOnlyChanged: {
    root.sample = ({})
    root.haveData = false
    root.loaded = false
    root.scrollAnchor = ""
    if (root.visible) root.refresh()
  }
  onAgentsChanged: Qt.callLater(root.restoreScroll)
}
