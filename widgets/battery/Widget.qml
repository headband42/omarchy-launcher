import QtQuick
import qs.Commons
import "../_kit"
import "battery.js" as Battery

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ battery: false, percentage: 0, state: "", minutesLeft: 0, rate: 0, onAc: true, profile: "", profiles: [] })

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
    poller.pollSoon()
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("battery.py")
    interval: 15000
    settleDelay: 800
    active: root.visible
    onSampled: function(data) { if (data) root.sample = data }
  }

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

    WidgetHeader {
      title: "POWER"
      dotColor: root.sample.battery && !root.charging && root.sample.percentage <= 15 ? Color.urgent : Color.accent
      dotOpacity: root.sample.battery ? 1 : 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
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
