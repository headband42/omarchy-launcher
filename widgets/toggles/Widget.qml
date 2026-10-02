import QtQuick
import qs.Commons
import "../_kit"
import "toggles.js" as Toggles

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ nightlight: false, stayAwake: false, dnd: false })

  readonly property var rows: Toggles.rowsFromSettings(root.tile && root.tile.settings)

  function flip(row) {
    if (!row || !row.command) return
    var next = {}
    for (var key in root.sample) next[key] = root.sample[key]
    next[row.id] = !next[row.id]
    root.sample = next
    Util.execDetached(row.command)
    poller.pollSoon()
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("toggles.py")
    interval: 5000
    // Re-read after a flip lands; nightlight settles over a second or so.
    settleDelay: 800
    active: root.visible
    onSampled: function(data) { if (data) root.sample = data }
  }

  Text {
    z: 1
    visible: root.rows.length === 0
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: "No toggles"
    color: root.foreground
    opacity: 0.45
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Column {
    z: 1
    visible: root.rows.length > 0
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    WidgetHeader {
      title: "TOGGLES"
      dotColor: Color.accent
      dotOpacity: 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Column {
      id: stack
      width: parent.width
      height: parent.height - parent.spacing - Style.font.caption - 4
      spacing: Style.space(6)

      Repeater {
        model: root.rows

        Item {
          required property var modelData
          width: stack.width
          height: (stack.height - stack.spacing * Math.max(0, root.rows.length - 1)) / Math.max(1, root.rows.length)

          Row {
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              y: Math.max(0, (parent.height - height) / 2)
              textFormat: Text.PlainText
              text: modelData.glyph
              color: root.foreground
              opacity: root.sample[modelData.id] ? 1 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width - Style.space(8) * 2 - Style.space(24)
              y: Math.max(0, (parent.height - height) / 2)
              textFormat: Text.PlainText
              text: modelData.label
              color: root.foreground
              opacity: root.sample[modelData.id] ? 0.9 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Rectangle {
            width: Style.space(18)
            height: Style.space(10)
            radius: height / 2
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: root.sample[modelData.id] ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

            Rectangle {
              width: parent.height - 4
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              x: root.sample[modelData.id] ? parent.width - width - 2 : 2
              color: root.foreground
              opacity: root.sample[modelData.id] ? 1 : 0.55

              Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.flip(modelData)
          }
        }
      }
    }
  }
}
