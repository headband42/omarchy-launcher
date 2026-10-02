import QtQuick
import qs.Commons
import "../_kit"
import "f1.js" as F1

// The race weekend (or the running order while a session is on), the
// championships, and the last race. The dots or the wheel turn the page.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowSec: Date.now() / 1000
  property int page: 0

  readonly property bool h24: {
    var format = Qt.locale().timeFormat(Locale.ShortFormat)
    return format.indexOf("AP") < 0 && format.indexOf("ap") < 0 && format.indexOf("A") < 0 && format.indexOf("a") < 0
  }
  readonly property var next: root.sample ? root.sample.next : null
  readonly property var live: root.sample && root.sample.live && !root.sample.live.finished ? root.sample.live : null
  readonly property var upcoming: root.next ? F1.nextSession(root.next.sessions, root.nowSec) : null

  function teamColour(hex) {
    var value = F1.colour(hex)
    return value || Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
  }

  Poller {
    script: Qt.resolvedUrl("f1.py")
    interval: root.sample && root.sample.pollMs ? Number(root.sample.pollMs) : 600000
    active: root.visible
    onSampled: function(data) { if (data) root.sample = data }
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.visible
    onTriggered: root.nowSec = Date.now() / 1000
  }

  // The wheel turns the page; clicks still reach the grid.
  MouseArea {
    z: 1
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      root.page = F1.nextPage(root.page, wheel.angleDelta.y < 0 ? 1 : -1)
      wheel.accepted = true
    }
  }

  // One standings or results line: position, team stripe, name, and a value.
  component Line: Item {
    id: line
    property string pos: ""
    property string colour: ""
    property string label: ""
    property string value: ""
    property bool strong: false
    width: parent ? parent.width : 0
    height: Style.font.bodySmall + Style.space(5)

    Text {
      id: posText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      textFormat: Text.PlainText
      text: line.pos
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }

    Rectangle {
      id: stripe
      anchors.left: posText.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(3)
      height: parent.height - Style.space(5)
      radius: 1
      color: root.teamColour(line.colour)
    }

    Text {
      anchors.left: stripe.right
      anchors.leftMargin: Style.space(6)
      anchors.right: valueText.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: line.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.weight: line.strong ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: line.value
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
  }

  component Caption: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.45
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.5
    elide: Text.ElideRight
  }

  Item {
    z: 2
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: root.next ? "F1 · ROUND " + root.next.round : "F1"
      trailing: F1.headerNote(root.sample, root.nowSec)
      dotColor: root.live ? Color.urgent : Color.accent
      dotOpacity: root.sample && root.sample.ok ? 1 : 0.35
      pulse: !!root.live
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Item {
      id: body
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.bottom: dots.top
      anchors.bottomMargin: Style.space(4)
      width: parent.width
      clip: true

      // —— Page 0: the weekend, or the running order ——
      Column {
        visible: root.page === 0 && !!root.next
        width: parent.width
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.next ? F1.shortRace(root.next.name) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.live ? root.live.name + " · running order"
            : (root.next ? [root.next.circuit, root.next.locality].filter(function(p) { return p }).join(" · ") : "")
          color: root.live ? Color.urgent : root.foreground
          opacity: root.live ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Item { width: 1; height: Style.space(4) }

        Repeater {
          model: root.live ? root.live.order.slice(0, 6) : []

          Line {
            required property var modelData
            pos: String(modelData.pos)
            colour: String(modelData.colour || "")
            label: String(modelData.code || "")
            value: String(modelData.team || "")
            strong: modelData.pos <= 3
          }
        }

        Repeater {
          model: root.live ? [] : (root.next ? root.next.sessions : [])

          Item {
            id: sessionRow
            required property var modelData
            readonly property string state: F1.sessionState(modelData, root.nowSec)
            readonly property bool isNext: !!root.upcoming && root.upcoming.start === modelData.start
            width: parent.width
            height: Style.font.bodySmall + Style.space(5)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(64)
              textFormat: Text.PlainText
              text: F1.shortSession(sessionRow.modelData.name)
              color: sessionRow.isNext ? Color.accent : root.foreground
              opacity: sessionRow.state === "done" ? 0.4 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: sessionRow.modelData.name === "Race" || sessionRow.isNext ? Font.DemiBold : Font.Normal
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: sessionRow.state === "done" ? "done" : (sessionRow.state === "live" ? "on now" : F1.clock(sessionRow.modelData.start, root.h24))
              color: sessionRow.isNext ? Color.accent : root.foreground
              opacity: sessionRow.state === "done" ? 0.4 : 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.features: { "tnum": 1 }
            }
          }
        }
      }

      // —— Page 1: the championships ——
      Column {
        visible: root.page === 1
        width: parent.width
        spacing: Style.space(1)

        Caption { text: "DRIVERS" + (root.sample && root.sample.season ? " · " + root.sample.season : "") }

        Repeater {
          model: root.sample ? root.sample.drivers.slice(0, 5) : []
          Line {
            required property var modelData
            pos: String(modelData.pos)
            colour: String(modelData.colour || "")
            label: String(modelData.name || modelData.code || "")
            value: String(modelData.points)
            strong: modelData.pos === "1"
          }
        }

        Item { width: 1; height: Style.space(4) }

        Caption { text: "CONSTRUCTORS" }

        Repeater {
          model: root.sample ? root.sample.teams.slice(0, 3) : []
          Line {
            required property var modelData
            pos: String(modelData.pos)
            colour: String(modelData.colour || "")
            label: String(modelData.name || "")
            value: String(modelData.points)
            strong: modelData.pos === "1"
          }
        }
      }

      // —— Page 2: the last race ——
      Column {
        visible: root.page === 2 && !!(root.sample && root.sample.last)
        width: parent.width
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.sample && root.sample.last ? F1.shortRace(root.sample.last.name) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Caption { text: root.sample && root.sample.last ? "ROUND " + root.sample.last.round + " · " + F1.dateText(root.sample.last.date).toUpperCase() : "" }

        Item { width: 1; height: Style.space(4) }

        Repeater {
          model: root.sample && root.sample.last ? root.sample.last.results.slice(0, 6) : []
          Line {
            required property var modelData
            pos: String(modelData.pos)
            colour: String(modelData.colour || "")
            label: String(modelData.name || modelData.code || "")
            value: String(modelData.time || "")
            strong: Number(modelData.pos) <= 3
          }
        }
      }

      Text {
        visible: !root.sample || root.sample.ok === false
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: !root.sample ? "Loading…" : String(root.sample.error || "No data")
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: dots
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(2)

      Repeater {
        model: F1.PAGES

        Item {
          id: dot
          required property int index
          width: Style.space(14)
          height: Style.space(10)

          Rectangle {
            anchors.centerIn: parent
            width: dot.index === root.page ? Style.space(10) : Style.space(5)
            height: Style.space(5)
            radius: height / 2
            color: dot.index === root.page ? Color.accent : root.foreground
            opacity: dot.index === root.page ? 1 : (dotMouse.containsMouse ? 0.6 : 0.3)
          }

          MouseArea {
            id: dotMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.page = dot.index
          }
        }
      }
    }
  }
}
