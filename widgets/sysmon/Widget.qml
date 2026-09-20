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
  property var sample: ({ cpu: 0, cpuMHz: 0, mem: 0, memUsed: 0, memTotal: 0, gpu: 0, gpuMHz: 0, vram: 0, vramUsed: 0, vramTotal: 0 })

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function fmtBytes(n) {
    var v = Number(n) || 0
    if (v >= 1073741824) return (v / 1073741824).toFixed(1) + "G"
    if (v >= 1048576) return (v / 1048576).toFixed(0) + "M"
    return (v / 1024).toFixed(0) + "K"
  }

  function fmtMhz(n) {
    var v = Number(n) || 0
    if (v >= 1000) return (v / 1000).toFixed(1) + "G"
    return v.toFixed(0) + "M"
  }

  Process {
    id: probe
    command: ["bash", root.scriptPath("sample.sh")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try { root.sample = JSON.parse(probeOut.text || "{}") } catch (e) { }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 1200
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  Component.onCompleted: probe.running = true
  onVisibleChanged: if (visible && !probe.running) probe.running = true

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    BarMeter {
      width: parent.width
      height: (parent.height - parent.spacing * 3) / 4
      label: "CPU"
      detail: fmtMhz(root.sample.cpuMHz) + " · " + Math.round(root.sample.cpu || 0) + "%"
      value: (root.sample.cpu || 0) / 100
      fontFamily: root.fontFamily
      foreground: root.foreground
      fill: Color.accent
    }
    BarMeter {
      width: parent.width
      height: (parent.height - parent.spacing * 3) / 4
      label: "RAM"
      detail: fmtBytes(root.sample.memUsed) + " / " + fmtBytes(root.sample.memTotal)
      value: (root.sample.mem || 0) / 100
      fontFamily: root.fontFamily
      foreground: root.foreground
      fill: Color.accent
    }
    BarMeter {
      width: parent.width
      height: (parent.height - parent.spacing * 3) / 4
      label: "GPU"
      detail: (root.sample.gpuMHz ? fmtMhz(root.sample.gpuMHz) + " · " : "") + Math.round(root.sample.gpu || 0) + "%"
      value: (root.sample.gpu || 0) / 100
      fontFamily: root.fontFamily
      foreground: root.foreground
      fill: Color.accent
    }
    BarMeter {
      width: parent.width
      height: (parent.height - parent.spacing * 3) / 4
      label: "VRAM"
      detail: fmtBytes(root.sample.vramUsed) + " / " + fmtBytes(root.sample.vramTotal)
      value: (root.sample.vram || 0) / 100
      fontFamily: root.fontFamily
      foreground: root.foreground
      fill: Color.accent
    }
  }
}
