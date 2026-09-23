import QtQuick
import Quickshell.Io
import qs.Commons

// Combined system + disks tile: slim CPU/RAM/GPU/VRAM rows on top,
// drive rows below. Reuses the sysmon and disks samplers next door,
// so there is only one copy of each sensor script.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ cpu: 0, cpuMHz: 0, mem: 0, memUsed: 0, memTotal: 0, gpu: 0, gpuMHz: 0, vram: 0, vramUsed: 0, vramTotal: 0 })
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

  readonly property bool gpuNA: !(Number(sample.gpu) > 0) && !(Number(sample.gpuMHz) > 0)
  readonly property bool vramNA: !(Number(sample.vramTotal) > 0)

  // Sensors with no data stay out of the way in the combined tile.
  readonly property var sysMeters: {
    var out = [
      { key: "cpu", label: "CPU", value: clamp01((Number(sample.cpu) || 0) / 100),
        pct: Math.round(Number(sample.cpu) || 0) + "%" },
      { key: "mem", label: "RAM", value: clamp01((Number(sample.mem) || 0) / 100),
        pct: Math.round(Number(sample.mem) || 0) + "%" }
    ]
    if (!gpuNA) out.push({ key: "gpu", label: "GPU", value: clamp01((Number(sample.gpu) || 0) / 100),
      pct: Math.round(Number(sample.gpu) || 0) + "%" })
    if (!vramNA) out.push({ key: "vram", label: "VRAM", value: clamp01((Number(sample.vram) || 0) / 100),
      pct: Math.round(Number(sample.vram) || 0) + "%" })
    return out
  }

  readonly property var visibleDrives: root.drives.slice(0, 4)
  readonly property int hiddenDrives: Math.max(0, root.drives.length - root.visibleDrives.length)

  // Single-line drive rows only when a slot is too short for two text rows.
  readonly property bool drivesCompact: {
    var n = Math.max(1, root.visibleDrives.length)
    return (diskCol.height / n) < Style.font.caption * 2 + Style.space(10)
  }

  readonly property real hot: {
    var m = 0
    var keys = ["cpu", "mem", "gpu", "vram"]
    for (var i = 0; i < keys.length; i++) {
      var p = clamp01((Number(sample[keys[i]]) || 0) / 100)
      if (p > m) m = p
    }
    for (var j = 0; j < root.drives.length; j++) {
      var d = root.drives[j] && root.drives[j].mounted ? (Number(root.drives[j].pct) || 0) / 100 : 0
      if (d > m) m = d
    }
    return clamp01(m)
  }

  Process {
    id: sysProbe
    command: ["bash", root.scriptPath("../sysmon/sample.sh")]
    stdout: StdioCollector { id: sysOut; waitForEnd: true }
    onExited: {
      try { root.sample = JSON.parse(sysOut.text || "{}") } catch (e) { }
      if (root.visible) sysPoll.restart()
    }
  }

  Timer {
    id: sysPoll
    interval: 1200
    onTriggered: if (root.visible && !sysProbe.running) sysProbe.running = true
  }

  Process {
    id: diskProbe
    command: ["/usr/bin/python3", root.scriptPath("../disks/sample.py")]
    stdout: StdioCollector { id: diskOut; waitForEnd: true }
    onExited: {
      try { root.drives = JSON.parse(diskOut.text || "[]") } catch (e) { root.drives = [] }
      if (root.visible) diskPoll.restart()
    }
  }

  Timer {
    id: diskPoll
    interval: 2000
    onTriggered: if (root.visible && !diskProbe.running) diskProbe.running = true
  }

  Component.onCompleted: { sysProbe.running = true; diskProbe.running = true }
  onVisibleChanged: {
    if (!visible) return
    if (!sysProbe.running) sysProbe.running = true
    if (!diskProbe.running) diskProbe.running = true
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

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
        text: "SYS · DISK"
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
        text: "MAX " + Math.round(root.hot * 100) + "%"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
      }
    }

    Column {
      id: sysCol
      width: parent.width
      spacing: Style.space(3)

      Repeater {
        model: root.sysMeters

        Row {
          required property var modelData
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: Style.space(38)
            textFormat: Text.PlainText
            text: modelData.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Item {
            width: parent.width - Style.space(38) - Style.space(36) - parent.spacing * 2
            height: sysPct.height

            Rectangle {
              anchors.centerIn: parent
              width: parent.width
              height: 5
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Rectangle {
                width: Math.max(height, modelData.value * parent.width)
                height: parent.height
                radius: parent.radius
                color: root.statusFill(modelData.value)
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }
          }

          Text {
            id: sysPct
            width: Style.space(36)
            textFormat: Text.PlainText
            text: modelData.pct
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
          }
        }
      }
    }

    Item {
      id: divider
      visible: root.drives.length > 0
      width: parent.width
      height: visible ? Style.font.caption + 2 : 0

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (moreText.visible ? moreText.width + Style.space(6) : 0)
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }

      Text {
        id: moreText
        visible: root.hiddenDrives > 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "+" + root.hiddenDrives + " more"
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      id: noDisksText
      visible: root.drives.length === 0
      width: parent.width
      height: visible ? implicitHeight : 0
      textFormat: Text.PlainText
      text: "No disks"
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Column {
      id: diskCol
      width: parent.width
      height: Math.max(0, parent.height - header.height - sysCol.height - divider.height - noDisksText.height - parent.spacing * 4)
      spacing: Style.space(3)
      clip: true

      Repeater {
        model: root.visibleDrives

        Item {
          required property var modelData
          width: parent.width
          height: (diskCol.height - diskCol.spacing * Math.max(0, root.visibleDrives.length - 1)) / Math.max(1, root.visibleDrives.length)

          Row {
            id: driveRow
            anchors.fill: parent
            spacing: Style.space(6)

            Item {
              id: ring
              width: parent.height
              height: parent.height
              property real value: modelData.mounted ? clamp01((Number(modelData.pct) || 0) / 100) : 0
              onValueChanged: ringCanvas.requestPaint()

              Canvas {
                id: ringCanvas
                anchors.fill: parent
                property color track: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                property color arc: root.statusFill(ring.value)
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onTrackChanged: requestPaint()
                onArcChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.clearRect(0, 0, width, height)
                  if (Math.min(width, height) < 4) return
                  var lw = Math.max(3, Math.round(Math.min(width, height) * 0.16))
                  var r = Math.min(width, height) / 2 - lw / 2
                  var cx = width / 2
                  var cy = height / 2
                  ctx.lineWidth = lw
                  ctx.lineCap = "butt"
                  ctx.beginPath()
                  ctx.arc(cx, cy, r, 0, Math.PI * 2)
                  ctx.strokeStyle = track
                  ctx.stroke()
                  if (ring.value > 0.005) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + ring.value * Math.PI * 2)
                    ctx.strokeStyle = arc
                    ctx.stroke()
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: ring.width >= 20
                textFormat: Text.PlainText
                text: modelData.mounted ? (Math.round(Number(modelData.pct) || 0) + "%") : "—"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Math.round(ring.width * 0.26))
                font.weight: Font.DemiBold
              }
            }

            Column {
              width: driveRow.width - ring.width - (driveCap.visible ? driveCap.width + driveRow.spacing : 0) - driveRow.spacing
              y: Math.max(0, (driveRow.height - height) / 2)
              spacing: 2

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.label || modelData.path || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                visible: !root.drivesCompact
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.mounted ? (fmtBytes(modelData.used) + "/" + fmtBytes(modelData.size)) : ("Not mounted · " + fmtBytes(modelData.size))
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Text {
              id: driveCap
              visible: root.drivesCompact
              width: Style.space(58)
              y: Math.max(0, (driveRow.height - height) / 2)
              textFormat: Text.PlainText
              text: modelData.mounted ? (fmtBytes(modelData.used) + "/" + fmtBytes(modelData.size)) : ("—/" + fmtBytes(modelData.size))
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              horizontalAlignment: Text.AlignRight
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              var path = String(modelData.path || "")
              var device = String(modelData.device || "")
              if (mouse.button === Qt.RightButton) {
                if (path && root.host && root.host.openTerminal) root.host.openTerminal(path)
                return
              }
              if (root.host && root.host.openVolume) root.host.openVolume(path, device)
            }
          }
        }
      }
    }

  }
}
