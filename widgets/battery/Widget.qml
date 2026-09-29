import QtQuick
import Quickshell.Io
import qs.Commons
import "battery.js" as Battery

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ battery: false, percentage: 0, state: "", minutesLeft: 0, rate: 0, onAc: true, profile: "", profiles: [] })

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  readonly property bool charging: sample.state === "charging"
  readonly property string glyph: root.charging ? "󰂄" : "󰁹"

  function cycleProfile() {
    var next = Battery.nextProfile(root.sample)
    if (!next) return
    var data = {}
    for (var key in root.sample) data[key] = root.sample[key]
    data.profile = next
    root.sample = data
    Util.execArgv(["omarchy-powerprofiles-set", "autodetect", next])
    settle.restart()
  }

  Process {
    id: probe
    command: ["/usr/bin/python3", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      try { root.sample = JSON.parse(probeOut.text || "{}") } catch (e) { }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 15000
    onTriggered: if (root.visible && !probe.running) probe.running = true
  }

  Timer {
    id: settle
    interval: 800
    onTriggered: if (!probe.running) probe.running = true
  }

  Component.onCompleted: probe.running = true
  onVisibleChanged: if (visible && !probe.running) probe.running = true

  MouseArea {
    z: 0
    anchors.fill: parent
    onClicked: {
      if (root.host && root.host.launchDefault) root.host.launchDefault()
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
        color: root.sample.battery && !root.charging && root.sample.percentage <= 15 ? Color.urgent : Color.accent
        opacity: root.sample.battery ? 1 : 0.35
      }

      Text {
        anchors.left: liveDot.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "POWER"
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
        visible: root.sample.battery
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.glyph
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.left: glyphText.visible ? glyphText.right : parent.left
        anchors.leftMargin: glyphText.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sample.battery ? (String(Math.round(Number(root.sample.percentage) || 0)) + "%") : "AC power"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: Battery.timeLine(root.sample)
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Item {
      id: profileRow
      width: parent.width
      height: Style.font.caption + 8

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Profile"
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Battery.profileLabel(root.sample.profile) || "—"
        color: root.foreground
        opacity: profileMouse.containsMouse ? 1 : 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      MouseArea {
        id: profileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.cycleProfile()
      }
    }
  }
}
