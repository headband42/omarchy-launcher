import QtQuick
import qs.Commons
import "../_kit"
import "network.js" as Net

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property var rate: null
  property var down: []
  property var up: []
  property var latency: null
  property bool copied: false

  readonly property bool online: !!(root.sample && root.sample.device)
  readonly property string vpns: Net.vpnLine(root.sample)

  function take(data) {
    if (!data || data.ok !== true) return
    var next = Net.pickRate(root.sample, data)
    if (root.sample && data.device !== root.sample.device) {
      root.down = []
      root.up = []
    }
    root.sample = data
    root.rate = next
    if (next) {
      root.down = Net.pushHistory(root.down, next.down)
      root.up = Net.pushHistory(root.up, next.up)
    }
  }

  function copyAddress() {
    var address = root.sample ? String(root.sample.ipv4 || root.sample.ipv6 || "") : ""
    if (!address) return
    Util.execArgv(["wl-copy", address])
    root.copied = true
    copiedTimer.restart()
  }

  Poller {
    script: Qt.resolvedUrl("network.py")
    interval: 1500
    active: root.visible
    onSampled: function(data) { root.take(data) }
  }

  Poller {
    script: Qt.resolvedUrl("network.py")
    args: ["--ping"]
    interval: 10000
    active: root.visible && root.online
    onSampled: function(data) { if (data) root.latency = data.latency }
  }

  Timer {
    id: copiedTimer
    interval: 1400
    onTriggered: root.copied = false
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "NETWORK"
      trailing: root.online ? Net.fmtLatency(root.latency) : ""
      dotColor: root.online ? Color.accent : Color.urgent
      dotOpacity: root.sample ? 1 : 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Item {
      id: hero
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      width: parent.width
      height: nameText.implicitHeight + detailText.implicitHeight + Style.space(2)

      Text {
        id: glyphText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sample ? Net.glyph(root.sample) : "󰤨"
        color: root.online ? Color.accent : root.foreground
        opacity: root.sample ? 1 : 0.35
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2)
      }

      Column {
        anchors.left: glyphText.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          id: nameText
          width: parent.width
          textFormat: Text.PlainText
          text: root.sample ? Net.title(root.sample) : "…"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          id: detailText
          width: parent.width
          textFormat: Text.PlainText
          text: root.sample ? Net.detail(root.sample) : "checking"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    // The address. A click copies it.
    Item {
      id: addressRow
      visible: root.online
      anchors.top: hero.bottom
      anchors.topMargin: Style.space(8)
      width: parent.width
      height: addressText.implicitHeight + Style.space(4)

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Style.space(4)
        anchors.rightMargin: -Style.space(4)
        radius: Style.space(4)
        color: root.foreground
        opacity: addressMouse.containsMouse ? 0.08 : 0
      }

      Text {
        id: addressText
        anchors.left: parent.left
        anchors.right: copyHint.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sample ? String(root.sample.ipv4 || root.sample.ipv6 || "no address") : ""
        color: root.foreground
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: copyHint
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.copied ? "copied" : "󰆏"
        color: root.copied ? Color.accent : root.foreground
        opacity: root.copied ? 1 : (addressMouse.containsMouse ? 0.8 : 0)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        id: addressMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.copyAddress()
      }
    }

    Row {
      id: rates
      visible: root.online
      anchors.top: addressRow.bottom
      anchors.topMargin: Style.space(6)
      width: parent.width

      Text {
        width: parent.width / 2
        textFormat: Text.PlainText
        text: "↓ " + Net.fmtRate(root.rate ? root.rate.down : null)
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      Text {
        width: parent.width / 2
        textFormat: Text.PlainText
        text: "↑ " + Net.fmtRate(root.rate ? root.rate.up : null)
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
      }
    }

    Canvas {
      id: graph
      visible: root.online && height > Style.space(12)
      anchors.top: rates.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: vpnText.visible ? vpnText.top : parent.bottom
      anchors.bottomMargin: vpnText.visible ? Style.space(6) : 0
      width: parent.width
      antialiasing: true

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var scale = Net.graphScale(root.down, root.up)
        var down = Net.graphPoints(root.down, width, height, scale)
        var up = Net.graphPoints(root.up, width, height, scale)
        ctx.lineWidth = 1.5
        ctx.lineJoin = "round"
        ctx.lineCap = "round"

        ctx.globalAlpha = 0.12
        ctx.strokeStyle = root.foreground
        ctx.beginPath()
        ctx.moveTo(0, height - 0.5)
        ctx.lineTo(width, height - 0.5)
        ctx.stroke()
        ctx.globalAlpha = 1

        var i
        if (down.length > 1) {
          ctx.beginPath()
          ctx.moveTo(down[0].x, height)
          for (i = 0; i < down.length; i++) ctx.lineTo(down[i].x, down[i].y)
          ctx.lineTo(down[down.length - 1].x, height)
          ctx.closePath()
          ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
          ctx.fill()
          ctx.beginPath()
          ctx.moveTo(down[0].x, down[0].y)
          for (i = 1; i < down.length; i++) ctx.lineTo(down[i].x, down[i].y)
          ctx.strokeStyle = Color.accent
          ctx.stroke()
        }
        if (up.length > 1) {
          ctx.globalAlpha = 0.6
          ctx.beginPath()
          ctx.moveTo(up[0].x, up[0].y)
          for (i = 1; i < up.length; i++) ctx.lineTo(up[i].x, up[i].y)
          ctx.strokeStyle = root.foreground
          ctx.stroke()
          ctx.globalAlpha = 1
        }
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
    }

    Text {
      id: vpnText
      visible: root.vpns.length > 0
      anchors.bottom: parent.bottom
      width: parent.width
      textFormat: Text.PlainText
      text: "󰖂  " + root.vpns
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  onDownChanged: graph.requestPaint()
  onUpChanged: graph.requestPaint()
  onForegroundChanged: graph.requestPaint()
}
