import QtQuick
import Quickshell.Io
import qs.Commons
import "updates.js" as Updates

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ ok: true, count: 0, names: [], omarchy: [], channel: "", version: "", lastUpgradeAt: 0 })
  property double nowMs: Date.now()

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  readonly property int count: Math.max(0, Number(sample.count) || 0)
  readonly property bool busy: probe.running && !sample.count && !sample.names
  readonly property string ago: Updates.fmtAgo(root.nowMs, sample.lastUpgradeAt)
  readonly property string versionLine: {
    var parts = []
    if (root.ago) parts.push("updated " + root.ago)
    else parts.push("never updated")
    if (root.sample.version) parts.push(String(root.sample.version))
    return parts.join(" · ")
  }

  Process {
    id: probe
    command: ["/usr/bin/python3", root.scriptPath("updates.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try { root.sample = JSON.parse(probeOut.text || "{}") } catch (e) { }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 1800000
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  Timer {
    interval: 60000
    running: root.visible
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Component.onCompleted: probe.running = true
  onVisibleChanged: if (visible && !probe.running) probe.running = true

  MouseArea {
    z: 0
    anchors.fill: parent
    onClicked: {
      if (root.host && root.host.launchDefault) root.host.launchDefault()
    }
  }

  Column {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

    Item {
      width: parent.width
      height: Style.font.caption + 4

      Rectangle {
        id: liveDot
        width: 6
        height: 6
        radius: 3
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.count > 0 ? Color.accent : root.foreground
        opacity: root.count > 0 ? 1 : 0.35

        SequentialAnimation on opacity {
          running: root.count > 0
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.4; duration: 900; easing.type: Easing.InOutQuad }
          NumberAnimation { from: 0.4; to: 1; duration: 900; easing.type: Easing.InOutQuad }
        }
      }

      Text {
        anchors.left: liveDot.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "UPDATES"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(root.sample.channel || "")
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
    }

    Item {
      width: parent.width
      height: Style.font.title + 6

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.busy ? "…" : (root.count > 0 ? String(root.count) : "✓")
        color: root.count > 0 ? Color.accent : root.foreground
        opacity: root.count > 0 ? 1 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(root.count > 0 && root.count < 10 ? 16 : 24)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.busy ? "checking" : (root.count > 0 ? (root.count === 1 ? "package" : "packages") : (root.sample.ok ? "up to date" : "couldn't check"))
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.versionLine
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: (root.sample.omarchy || []).length > 0
      textFormat: Text.PlainText
      text: (root.sample.omarchy || []).length > 0 ? String(root.sample.omarchy[0]) : ""
      color: Color.accent
      opacity: 0.85
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
