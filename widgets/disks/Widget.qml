import QtQuick
import Quickshell
import qs.Commons
import "../_kit"

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

  Poller {
    id: poller
    script: Qt.resolvedUrl("../_kit/disks.py")
    interval: 2000
    active: root.visible
    onSampled: function(data) { root.drives = Array.isArray(data) ? data : [] }
  }

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

    WidgetHeader {
      id: header
      title: "STORAGE"
      dotColor: root.statusFill(root.hot)
      pulse: true
      fontFamily: root.fontFamily
      foreground: root.foreground
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
