import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ cpu: 0, cpuMHz: 0, cpuModel: "", cpuCores: 0, cpuThreads: 0, mem: 0, memUsed: 0, memTotal: 0, memConfig: "", gpu: 0, gpuMHz: 0, gpuModel: "", vram: 0, vramUsed: 0, vramTotal: 0, sysDrive: "" })
  property var peaks: ({ cpu: 0, mem: 0, gpu: 0, vram: 0 })

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

  // Static hardware lines for the info section; only known specs appear.
  readonly property var specLines: {
    var out = []
    var cpuBits = []
    if (sample.cpuModel) cpuBits.push(String(sample.cpuModel))
    var c = Math.round(Number(sample.cpuCores) || 0)
    var t = Math.round(Number(sample.cpuThreads) || 0)
    if (c > 0 && t > 0) cpuBits.push(c + "C/" + t + "T")
    else if (t > 0) cpuBits.push(t + "T")
    if (cpuBits.length > 0) out.push(cpuBits.join(" · "))
    if (sample.memConfig) out.push(String(sample.memConfig))
    if (sample.gpuModel) out.push(String(sample.gpuModel))
    if (sample.sysDrive) out.push(String(sample.sysDrive))
    return out
  }

  function clamp01(v) {
    var x = Number(v) || 0
    return Math.max(0, Math.min(1, x))
  }

  // Calm accent normally, blending into urgent as a meter runs hot.
  function statusFill(v) {
    var x = clamp01(v)
    if (x >= 0.9) return Color.urgent
    if (x >= 0.75) {
      var t = (x - 0.75) / 0.15
      return Qt.rgba(Color.accent.r + (Color.urgent.r - Color.accent.r) * t,
                     Color.accent.g + (Color.urgent.g - Color.accent.g) * t,
                     Color.accent.b + (Color.urgent.b - Color.accent.b) * t, 1)
    }
    return Color.accent
  }

  readonly property real hot: Math.max(clamp01((Number(sample.cpu) || 0) / 100),
                                       clamp01((Number(sample.mem) || 0) / 100),
                                       clamp01((Number(sample.gpu) || 0) / 100),
                                       clamp01((Number(sample.vram) || 0) / 100))

  readonly property bool gpuNA: !(Number(sample.gpu) > 0) && !(Number(sample.gpuMHz) > 0)
  readonly property bool vramNA: !(Number(sample.vramTotal) > 0)

  readonly property var meters: [
    { key: "cpu", label: "CPU", value: clamp01((Number(sample.cpu) || 0) / 100),
      pct: Math.round(Number(sample.cpu) || 0) + "%", sub: fmtMhz(sample.cpuMHz) },
    { key: "mem", label: "RAM", value: clamp01((Number(sample.mem) || 0) / 100),
      pct: Math.round(Number(sample.mem) || 0) + "%", sub: fmtBytes(sample.memUsed) + " / " + fmtBytes(sample.memTotal) },
    { key: "gpu", label: "GPU", value: gpuNA ? 0 : clamp01((Number(sample.gpu) || 0) / 100),
      pct: gpuNA ? "—" : Math.round(Number(sample.gpu) || 0) + "%",
      sub: gpuNA ? "n/a" : (Number(sample.gpuMHz) > 0 ? fmtMhz(sample.gpuMHz) : "load") },
    { key: "vram", label: "VRAM", value: vramNA ? 0 : clamp01((Number(sample.vram) || 0) / 100),
      pct: vramNA ? "—" : Math.round(Number(sample.vram) || 0) + "%",
      sub: vramNA ? "n/a" : fmtBytes(sample.vramUsed) + " / " + fmtBytes(sample.vramTotal) }
  ]

  // Peak-hold markers: track the recent maximum, then let it decay slowly.
  onSampleChanged: {
    var next = {}
    var keys = ["cpu", "mem", "gpu", "vram"]
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      var v = clamp01((Number(root.sample[k]) || 0) / 100)
      var old = (root.peaks && Number(root.peaks[k])) || 0
      next[k] = Math.max(v, old - 0.02)
    }
    root.peaks = next
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
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    Item {
      id: header
      width: parent.width
      height: Style.font.caption + 4

      Rectangle {
        id: liveDot
        width: 6
        height: 6
        radius: 3
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.statusFill(root.hot)

        SequentialAnimation on opacity {
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
        text: "SYSTEM"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

    }

    Item {
      id: barsWrap
      width: parent.width
      height: parent.height - header.height - (specWrap.visible ? specWrap.height + parent.spacing : 0) - parent.spacing

      Column {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Repeater {
          model: root.meters

          Column {
            required property var modelData
            width: stack.width
            spacing: 2

            Row {
              id: meterRow
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: meterLabel
                width: Style.space(46)
                height: meterPct.height
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
              }

              Item {
                width: meterRow.width - meterLabel.width - meterPct.width - meterRow.spacing * 2
                height: meterPct.height

                Rectangle {
                  anchors.centerIn: parent
                  width: parent.width
                  height: 6
                  radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                  Rectangle {
                    width: Math.max(height, modelData.value * parent.width)
                    height: parent.height
                    radius: parent.radius
                    color: root.statusFill(modelData.value)
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                  }

                  Rectangle {
                    visible: (root.peaks[modelData.key] || 0) > 0.02
                    width: 2
                    height: parent.height
                    radius: 1
                    x: Math.min(parent.width - width, Math.max(0, (root.peaks[modelData.key] || 0) * parent.width - width / 2))
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.5)
                  }
                }
              }

              Text {
                id: meterPct
                width: Style.space(44)
                textFormat: Text.PlainText
                text: modelData.pct
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
              }
            }

            Text {
              x: Style.space(46) + Style.space(8)
              width: parent.width - x
              textFormat: Text.PlainText
              text: modelData.sub
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    Column {
      id: specWrap
      visible: root.specLines.length > 0
      width: parent.width
      spacing: Style.space(4)

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }

      Column {
        width: parent.width
        spacing: 1

        Repeater {
          model: root.specLines

          Text {
            required property var modelData
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData)
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
