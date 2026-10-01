import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var drives: []

  // Single-line rows only when a slot is too short for two text rows.
  readonly property bool compact: {
    var n = Math.max(1, root.drives.length)
    return (stack.height / n) < Style.font.caption * 2 + Style.space(10)
  }

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

  // Calm accent normally, blending into urgent as a volume fills up.
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

  readonly property real hot: {
    var m = 0
    for (var i = 0; i < root.drives.length; i++) {
      var p = root.drives[i] && root.drives[i].mounted ? (Number(root.drives[i].pct) || 0) / 100 : 0
      if (p > m) m = p
    }
    return clamp01(m)
  }

  Process {
    id: probe
    command: ["/usr/bin/python3", root.scriptPath("../_kit/disks.py")]
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

  MouseArea {
    z: 0
    anchors.fill: parent
    onClicked: {
      if (root.host && root.host.openVolume)
        root.host.openVolume(Quickshell.env("HOME") || "", "")
    }
  }

  Text {
    z: 1
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
    z: 1
    visible: root.drives.length > 0
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
        text: "STORAGE"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

    }

    Column {
      id: stack
      width: parent.width
      height: parent.height - header.height - parent.spacing
      spacing: root.compact ? Style.space(3) : Style.space(6)

      Repeater {
        model: root.drives

        Item {
          required property var modelData
          width: parent.width
          height: (stack.height - stack.spacing * Math.max(0, root.drives.length - 1)) / Math.max(1, root.drives.length)

          Row {
            id: driveRow
            anchors.fill: parent
            spacing: Style.space(8)

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
              width: driveRow.width - ring.width - (compactDetail.visible ? compactDetail.width + driveRow.spacing : 0) - driveRow.spacing
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
                visible: !root.compact
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.mounted ? (fmtBytes(modelData.used) + " / " + fmtBytes(modelData.size)) : ("Not mounted · " + fmtBytes(modelData.size))
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Text {
              id: compactDetail
              visible: root.compact
              width: Style.space(64)
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
