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

  function fmtBytes(n) {
    var v = Number(n) || 0
    if (v >= 1099511627776) return (v / 1099511627776).toFixed(1) + "T"
    if (v >= 1073741824) return (v / 1073741824).toFixed(1) + "G"
    if (v >= 1048576) return (v / 1048576).toFixed(0) + "M"
    return (v / 1024).toFixed(0) + "K"
  }

  Process {
    id: probe
    command: ["python3", Qt.resolvedUrl("sample.py").toString().replace("file://", "")]
    running: root.visible
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.drives = JSON.parse(text() || "[]") } catch (e) { root.drives = [] }
      }
    }
    onExited: poll.restart()
  }

  Timer {
    id: poll
    interval: 2000
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  onVisibleChanged: if (visible) probe.running = true

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(2)

    Repeater {
      model: root.drives

      Item {
        required property var modelData
        width: parent.width
        height: Math.max(Style.space(18), Math.floor((parent.parent.height - Style.space(8)) / Math.max(1, root.drives.length)))

        BarMeter {
          anchors.fill: parent
          label: String(modelData.label || modelData.path || "")
          detail: fmtBytes(modelData.used) + "/" + fmtBytes(modelData.size)
          value: (Number(modelData.pct) || 0) / 100
          fontFamily: root.fontFamily
          foreground: root.foreground
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
