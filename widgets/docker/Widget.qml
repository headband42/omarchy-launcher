import QtQuick
import Quickshell.Io
import qs.Commons
import "docker.js" as Docker

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ ok: false, mode: "error", running: 0, stopped: 0, unhealthy: 0, rows: [] })

  readonly property var rows: (root.sample && root.sample.rows) || []
  readonly property bool compact: {
    var n = Math.max(1, root.rows.length)
    return (stack.height / n) < Style.font.caption + Style.space(8)
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function openTui() {
    if (root.host && root.host.launchDefault) root.host.launchDefault()
  }

  Process {
    id: probe
    command: ["/usr/bin/python3", root.scriptPath("docker.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try { root.sample = JSON.parse(probeOut.text || "{}") } catch (e) { }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 10000
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  Component.onCompleted: probe.running = true
  onVisibleChanged: if (visible && !probe.running) probe.running = true

  MouseArea {
    z: 0
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.openTui()
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
        color: root.sample.ok ? (root.sample.unhealthy > 0 ? Color.urgent : Color.accent) : root.foreground
        opacity: root.sample.ok ? 1 : 0.35
      }

      Text {
        anchors.left: liveDot.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "DOCKER"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.sample.ok ? Docker.countsLine(root.sample) : Docker.statusLabel(root.sample)
      color: root.foreground
      opacity: root.sample.ok ? 0.9 : 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: Docker.statusHint(root.sample) !== ""
      textFormat: Text.PlainText
      text: Docker.statusHint(root.sample)
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Column {
      id: stack
      width: parent.width
      height: parent.height - Style.font.caption - 4 - (Docker.statusHint(root.sample) !== "" ? Style.font.caption + parent.spacing : 0) - parent.spacing * 2 - Style.font.body
      visible: root.sample.ok && root.rows.length > 0
      spacing: Style.space(3)

      Repeater {
        model: root.rows

        Item {
          required property var modelData
          width: stack.width
          height: (stack.height - stack.spacing * Math.max(0, root.rows.length - 1)) / Math.max(1, root.rows.length)

          Row {
            anchors.fill: parent
            spacing: Style.space(6)

            Rectangle {
              width: Style.space(6)
              height: width
              radius: width / 2
              y: Math.max(0, (parent.height - height) / 2)
              color: modelData.unhealthy ? Color.urgent : (modelData.running ? Color.accent : root.foreground)
              opacity: modelData.running ? 1 : 0.35
            }

            Text {
              width: parent.width - Style.space(6) - (root.compact ? Style.space(6) : Style.space(52))
              y: Math.max(0, (parent.height - height) / 2)
              textFormat: Text.PlainText
              text: String(modelData.name || "")
              color: root.foreground
              opacity: modelData.running ? 0.9 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            visible: !root.compact
            width: Style.space(52)
            anchors.right: parent.right
            y: Math.max(0, (parent.height - height) / 2)
            textFormat: Text.PlainText
            text: String(modelData.status || "")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openTui()
          }
        }
      }
    }
  }
}
