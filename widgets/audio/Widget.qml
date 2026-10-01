import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ volume: 0, muted: false, sink: "", sinks: [], index: -1 })

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  readonly property int volume: Math.max(0, Math.min(100, Math.round(Number(sample.volume) || 0)))
  readonly property real fill: root.sample.muted ? 0 : root.volume / 100

  function act(command) {
    Util.execDetached(command)
    settle.restart()
  }

  function bump(delta) {
    var next = Math.max(0, Math.min(100, root.volume + delta))
    var data = {}
    for (var key in root.sample) data[key] = root.sample[key]
    data.volume = next
    data.muted = false
    root.sample = data
    act("omarchy-audio-output-volume " + (delta > 0 ? "raise" : "lower"))
  }

  function toggleMute() {
    var data = {}
    for (var key in root.sample) data[key] = root.sample[key]
    data.muted = !data.muted
    root.sample = data
    act("omarchy-audio-output-volume mute-toggle")
  }

  Process {
    id: probe
    command: ["/usr/bin/python3", root.scriptPath("audio.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try { root.sample = JSON.parse(probeOut.text || "{}") } catch (e) { }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 3000
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  Timer {
    id: settle
    interval: 500
    onTriggered: if (!probe.running) probe.running = true
  }

  Component.onCompleted: probe.running = true
  onVisibleChanged: if (visible && !probe.running) probe.running = true

  MouseArea {
    z: 0
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onWheel: function(wheel) {
      root.bump(wheel.angleDelta.y > 0 ? 5 : -5)
      wheel.accepted = true
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        if (root.host && root.host.launchDefault) root.host.launchDefault()
        return
      }
      root.toggleMute()
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
        color: root.sample.muted ? root.foreground : Color.accent
        opacity: root.sample.muted ? 0.35 : 1
      }

      Text {
        anchors.left: liveDot.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "AUDIO"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }
    }

    Item {
      width: parent.width
      height: Style.font.title + 6

      Text {
        id: glyphText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sample.muted ? "󰝟" : "󰕾"
        color: root.foreground
        opacity: root.sample.muted ? 0.45 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.left: glyphText.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sample.muted ? "muted" : (String(root.volume) + "%")
        color: root.foreground
        opacity: root.sample.muted ? 0.55 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(6)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

      Rectangle {
        width: parent.width * root.fill
        height: parent.height
        radius: parent.radius
        color: root.sample.muted ? root.foreground : Color.accent
        opacity: root.sample.muted ? 0.35 : 1

        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
      }
    }

    Item {
      id: sinkRow
      width: parent.width
      height: Style.font.caption + 8

      Text {
        anchors.fill: parent
        anchors.topMargin: Style.space(4)
        textFormat: Text.PlainText
        text: root.sample.sink || "no output"
        color: root.foreground
        opacity: sinkMouse.containsMouse ? 0.9 : 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }

      MouseArea {
        id: sinkMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.act("omarchy-audio-output-switch")
      }
    }
  }
}
