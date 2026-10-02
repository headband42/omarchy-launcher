import QtQuick
import qs.Commons
import "../_kit"
import "../_kit/kit.js" as Kit
import "timer.js" as Countdown

// Countdowns on Omarchy's own reminders. Each one is a systemd user timer, so
// it fires its notification whether or not the launcher is open.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var reminders: []
  property bool available: true
  property double nowSec: Math.floor(Date.now() / 1000)

  readonly property var presets: Countdown.presets(root.tile && root.tile.settings)
  readonly property var running: Countdown.live(root.reminders, root.nowSec)
  readonly property var next: root.running.length > 0 ? root.running[0] : null
  readonly property var others: root.running.slice(1)

  function start(minutes) {
    Util.execArgv(["omarchy-reminder", String(minutes)])
    poller.pollSoon()
  }

  function cancel(row) {
    if (!row || !row.unit) return
    Util.execArgv(["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("timer.py")), "--cancel", String(row.unit)])
    var keep = []
    for (var i = 0; i < root.reminders.length; i++) if (root.reminders[i].unit !== row.unit) keep.push(root.reminders[i])
    root.reminders = keep
    poller.pollSoon()
  }

  function clockAt(epoch) {
    return Qt.formatTime(new Date(Number(epoch) * 1000), Qt.locale().timeFormat(Locale.ShortFormat))
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("timer.py")
    interval: 5000
    active: root.visible
    settleDelay: 600
    onSampled: function(data) {
      if (!data) return
      root.available = data.ok === true
      root.reminders = Array.isArray(data.reminders) ? data.reminders : []
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: root.nowSec = Math.floor(Date.now() / 1000)
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "TIMER"
      trailing: root.running.length > 1 ? root.running.length + " running" : (root.next ? "ends " + root.clockAt(root.next.at) : "")
      dotColor: root.next ? Color.accent : root.foreground
      dotOpacity: root.next ? 1 : 0.35
      pulse: !!root.next
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // The soonest countdown, with a bar for how much has run.
    Item {
      id: hero
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      width: parent.width
      height: big.implicitHeight + caption.implicitHeight + progress.height + Style.space(6)

      Text {
        id: big
        anchors.left: parent.left
        anchors.top: parent.top
        textFormat: Text.PlainText
        text: root.next ? Countdown.fmtCountdown(Countdown.remaining(root.next, root.nowSec)) : "0:00"
        color: root.next ? Color.accent : root.foreground
        opacity: root.next ? 1 : 0.3
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2.4)
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
      }

      IconButton {
        visible: !!root.next
        anchors.right: parent.right
        anchors.verticalCenter: big.verticalCenter
        glyph: "󰅖"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.cancel(root.next)
      }

      Text {
        id: caption
        anchors.top: big.bottom
        width: parent.width
        textFormat: Text.PlainText
        text: !root.available ? "omarchy-reminder is not available"
          : (root.next ? Countdown.label(root.next) : "Pick a length to start")
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Rectangle {
        id: progress
        anchors.top: caption.bottom
        anchors.topMargin: Style.space(6)
        width: parent.width
        height: Style.space(4)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

        Rectangle {
          width: parent.width * (root.next ? Countdown.elapsed(root.next, root.nowSec) : 0)
          height: parent.height
          radius: parent.radius
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 400 } }
        }
      }
    }

    // The rest, soonest first.
    ListView {
      id: list
      anchors.top: hero.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: presetRow.top
      anchors.bottomMargin: Style.space(6)
      width: parent.width
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      model: root.others

      delegate: Item {
        id: row
        required property var modelData
        width: ListView.view.width
        height: Style.space(22)

        Text {
          anchors.left: parent.left
          anchors.right: remainingText.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Countdown.label(row.modelData)
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          id: remainingText
          anchors.right: dropButton.left
          anchors.rightMargin: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Countdown.fmtCountdown(Countdown.remaining(row.modelData, root.nowSec))
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
        }

        IconButton {
          id: dropButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(20)
          glyph: "󰅖"
          glyphSize: Style.font.caption
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.cancel(row.modelData)
        }
      }
    }

    Row {
      id: presetRow
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)

      Repeater {
        model: root.presets

        IconButton {
          required property var modelData
          width: Math.floor((presetRow.parent.width - presetRow.spacing * (root.presets.length - 1)) / root.presets.length)
          label: Countdown.fmtPreset(modelData)
          labelSize: Style.font.caption
          filled: true
          available: root.available
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.start(modelData)
        }
      }
    }
  }
}
