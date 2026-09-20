import QtQuick
import Quickshell.Io
import qs.Commons
import ".."

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var drives: []

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function fmtBytes(n) {
    var v = Number(n) || 0
    if (v >= 1099511627776) return (v / 1099511627776).toFixed(1) + "T"
    if (v >= 1073741824) return (v / 1073741824).toFixed(1) + "G"
    if (v >= 1048576) return (v / 1048576).toFixed(0) + "M"
    return (v / 1024).toFixed(0) + "K"
  }

  Process {
    id: probe
    command: ["/usr/bin/python3", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try { root.drives = JSON.parse(probeOut.text || "[]") } catch (e) { root.drives = [] }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 2000
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  Component.onCompleted: probe.running = true
  onVisibleChanged: if (visible && !probe.running) probe.running = true

  Text {
    visible: root.drives.length === 0
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: "No disks"
    color: root.foreground
    opacity: 0.45
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Column {
    visible: root.drives.length > 0
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(4)

    Repeater {
      model: root.drives

      Item {
        required property var modelData
        width: parent.width
        height: Math.max(Style.space(22), Math.floor((parent.height - parent.spacing * Math.max(0, root.drives.length - 1)) / Math.max(1, root.drives.length)))

        BarMeter {
          anchors.fill: parent
          compact: root.drives.length > 3
          label: String(modelData.label || modelData.path || "")
          detail: fmtBytes(modelData.used) + " / " + fmtBytes(modelData.size)
          value: (Number(modelData.pct) || 0) / 100
          fontFamily: root.fontFamily
          foreground: root.foreground
          fill: Color.accent
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            var path = String(modelData.path || "")
            if (!path) return
            if (mouse.button === Qt.RightButton) {
              if (root.host && root.host.openTerminal) root.host.openTerminal(path)
            } else if (root.host && root.host.openFolder) {
              root.host.openFolder(path)
            }
          }
        }
      }
    }
  }
}
