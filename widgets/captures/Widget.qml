import QtQuick
import qs.Commons
import qs.Ui
import "../_kit"
import "captures.js" as Captures

// The newest screenshot, and buttons for Omarchy's capture commands. A capture
// closes the launcher first so it is not in the picture.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowSec: Date.now() / 1000
  property bool copied: false

  readonly property var shot: root.sample ? root.sample.screenshot : null
  readonly property bool recording: !!(root.sample && root.sample.recordingActive)

  function closeLauncher() {
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  function capture(action) {
    if (!action) return
    // Stopping a recording needs no pause: nothing is being pictured.
    if (action.id === "record" && root.recording) {
      Util.execArgv(action.argv)
      poller.pollSoon()
      return
    }
    Util.execArgv(Captures.delayed(action.argv, Captures.CLOSE_DELAY))
    root.closeLauncher()
  }

  function openShot() {
    if (!root.shot || !root.shot.path) return
    Util.execArgv(["xdg-open", String(root.shot.path)])
    root.closeLauncher()
  }

  function copyShot() {
    if (!root.shot || !root.shot.path) return
    Util.execArgv(Captures.copyArgv(root.shot.path))
    root.copied = true
    copiedTimer.restart()
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("captures.py")
    interval: 5000
    active: root.visible
    onSampled: function(data) { if (data && data.ok === true) root.sample = data }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.nowSec = Date.now() / 1000
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
      title: "CAPTURES"
      trailing: Captures.headerNote(root.sample, root.nowSec)
      dotColor: root.recording ? Color.urgent : (root.shot ? Color.accent : root.foreground)
      dotOpacity: root.recording || root.shot ? 1 : 0.35
      pulse: root.recording
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // The newest screenshot. A click opens it; the corner button copies it.
    Item {
      id: preview
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.bottom: caption.top
      anchors.bottomMargin: Style.space(4)
      width: parent.width

      Rectangle {
        anchors.fill: parent
        radius: Style.space(6)
        color: root.foreground
        opacity: 0.06
      }

      Image {
        id: thumb
        anchors.fill: parent
        anchors.margins: Style.space(4)
        source: root.shot && root.shot.path ? "file://" + root.shot.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        sourceSize.width: Math.max(64, Math.round(width * 2))
      }

      Column {
        visible: !root.shot
        anchors.centerIn: parent
        width: parent.width - Style.space(16)
        spacing: Style.space(4)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "󰄀"
          color: root.foreground
          opacity: 0.35
          font.family: root.fontFamily
          font.pixelSize: Math.round(Style.font.title * 2)
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.sample ? "No screenshots yet" : "…"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: previewMouse
        anchors.fill: parent
        enabled: !!root.shot
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.openShot()
      }

      IconButton {
        visible: !!root.shot && (previewMouse.containsMouse || hovered || root.copied)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)
        glyph: root.copied ? "󰄬" : "󰆏"
        filled: true
        tint: root.copied ? Color.accent : root.foreground
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.copyShot()
      }
    }

    Text {
      id: caption
      anchors.bottom: actions.top
      anchors.bottomMargin: Style.space(8)
      width: parent.width
      textFormat: Text.PlainText
      text: root.copied ? "Copied to the clipboard" : Captures.shotCaption(root.shot, root.nowSec)
      color: root.copied ? Color.accent : root.foreground
      opacity: root.copied ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Row {
      id: actions
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: Captures.ACTIONS

        Item {
          id: action
          required property var modelData
          readonly property bool stop: modelData.id === "record" && root.recording
          width: (actions.width - actions.spacing * (Captures.ACTIONS.length - 1)) / Captures.ACTIONS.length
          height: Style.space(40)

          Rectangle {
            anchors.fill: parent
            radius: Style.space(6)
            color: action.stop ? Color.urgent : root.foreground
            opacity: action.stop ? (actionMouse.containsMouse ? 0.35 : 0.22) : (actionMouse.containsMouse ? 0.16 : 0.07)
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(1)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: action.stop ? "󰓛" : action.modelData.glyph
              color: action.stop ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: action.stop ? "Stop" : action.modelData.label
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.capture(action.modelData)
          }
        }
      }
    }
  }
}
