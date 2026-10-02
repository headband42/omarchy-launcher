import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import "../_kit"
import "bluetooth.js" as Bt

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var pending: ({})
  property double nowMs: Date.now()

  readonly property var adapter: Bluetooth.defaultAdapter
  property bool hasAdapter: !!root.adapter
  property bool powered: !!(root.adapter && root.adapter.enabled)
  property var deviceRows: Bt.rows(Bluetooth.devices ? Bluetooth.devices.values : [], root.pending, root.nowMs)
  readonly property int connected: Bt.connectedCount(root.deviceRows)
  readonly property bool waiting: {
    for (var i = 0; i < root.deviceRows.length; i++) if (root.deviceRows[i].pending) return true
    return false
  }

  function act(row, action) {
    if (!row || !Bt.isAddress(row.address)) return
    root.pending = Bt.withPending(root.pending, row.address, action, Date.now())
    root.nowMs = Date.now()
    Util.execArgv(["omarchy-bluetooth-device", action, row.address])
  }

  function togglePower() {
    Util.execArgv(["omarchy-bluetooth-power", root.powered ? "off" : "on"])
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible && root.waiting
    onTriggered: root.nowMs = Date.now()
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      width: parent.width - power.width - Style.space(4)
      title: "BLUETOOTH"
      trailing: !root.hasAdapter ? "" : (!root.powered ? "off" : (root.connected > 0 ? root.connected + " connected" : ""))
      dotColor: root.connected > 0 ? Color.accent : root.foreground
      dotOpacity: root.powered ? (root.connected > 0 ? 1 : 0.6) : 0.25
      pulse: root.waiting
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    IconButton {
      id: power
      visible: root.hasAdapter
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      glyph: root.powered ? "󰂯" : "󰂲"
      tint: root.powered ? Color.accent : root.foreground
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.togglePower()
    }

    ListView {
      id: list
      visible: root.powered && root.deviceRows.length > 0
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.bottom: parent.bottom
      width: parent.width
      clip: true
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.deviceRows

      delegate: Item {
        id: row
        required property var modelData
        width: ListView.view.width
        height: Style.space(30)

        readonly property bool hot: rowMouse.containsMouse || drop.hovered

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: root.foreground
          opacity: row.hot ? 0.07 : 0
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.modelData.connected || row.modelData.pending ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: if (!row.modelData.connected && !row.modelData.pending) root.act(row.modelData, "connect")
        }

        Text {
          id: glyph
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          textFormat: Text.PlainText
          text: row.modelData.glyph
          color: row.modelData.connected ? Color.accent : root.foreground
          opacity: row.modelData.connected ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Text {
          anchors.left: glyph.right
          anchors.leftMargin: Style.space(4)
          anchors.right: note.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.name
          color: root.foreground
          opacity: row.modelData.connected ? 1 : 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          id: note
          visible: !(row.modelData.connected && !row.modelData.pending && row.hot)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Bt.rowNote(row.modelData)
          color: row.modelData.battery !== null && row.modelData.battery <= 15 && row.modelData.connected ? Color.urgent : root.foreground
          opacity: row.modelData.pending ? 0.8 : (row.modelData.connected ? 0.75 : (row.hot ? 0.8 : 0))
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
        }

        IconButton {
          id: drop
          visible: row.modelData.connected && !row.modelData.pending && row.hot
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(22)
          glyph: "󰅖"
          glyphSize: Style.font.caption
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.act(row.modelData, "disconnect")
        }
      }
    }

    Column {
      visible: !list.visible
      anchors.top: header.bottom
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(10)
      topPadding: Math.max(0, (height - implicitHeight) / 2 - Style.space(6))

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: !root.hasAdapter ? "󰂲" : (!root.powered ? "󰂲" : "󰂯")
        color: root.foreground
        opacity: 0.35
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2.2)
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: !root.hasAdapter ? "No Bluetooth adapter" : (!root.powered ? "Bluetooth is off" : "No paired devices")
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      IconButton {
        visible: root.hasAdapter
        anchors.horizontalCenter: parent.horizontalCenter
        glyph: root.powered ? "󰐕" : "󰂯"
        label: root.powered ? "Pair a device" : "Turn on"
        filled: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          if (!root.powered) root.togglePower()
          else if (root.host && root.host.launchDefault) root.host.launchDefault()
        }
      }
    }
  }
}
