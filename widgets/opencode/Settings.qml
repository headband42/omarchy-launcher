import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root
  focus: true

  property var tile: ({})
  property var settings: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color hoverFill: Color.menu.background
  property var borderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius

  property int selectedIndex: 0

  // Go's three usage blocks, and the reset style, are the whole model of
  // this tile. Everything here is a plain option, so it follows the widget.
  readonly property var hidden: String((root.settings && root.settings.hidden) || "")
  readonly property string resetStyle: String((root.settings && root.settings.resetStyle) || "relative")
  readonly property bool showAmounts: !(root.settings && root.settings.showAmounts === false)
  readonly property int contentWidth: Style.space(340)

  readonly property var blocks: [
    { id: "fiveHour", label: "5-hour block", note: "resets every 5 hours" },
    { id: "week", label: "Weekly block", note: "resets every week" },
    { id: "month", label: "Monthly block", note: "resets with the plan" }
  ]

  function isHidden(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    return list.indexOf(String(id)) >= 0
  }

  function toggle(id) {
    var list = root.hidden.length ? root.hidden.split(",") : []
    var at = list.indexOf(String(id))
    if (at >= 0) list.splice(at, 1)
    else list.push(String(id))
    root.commit(list.join(","), root.resetStyle, root.showAmounts)
  }

  function setStyle(style) {
    root.commit(root.hidden, style, root.showAmounts)
  }

  function toggleAmounts() {
    root.commit(root.hidden, root.resetStyle, !root.showAmounts)
  }

  function showAll() {
    root.commit("", root.resetStyle, root.showAmounts)
  }

  function commit(hidden, style, amounts) {
    root.settings = { hidden: String(hidden || ""), resetStyle: String(style || "relative"), showAmounts: amounts !== false }
    root.forceActiveFocus()
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.blocks.length
    if (event.key === Qt.Key_Up && count > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + count) % count
      return true
    }
    if (event.key === Qt.Key_Down && count > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % count
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.toggle(root.blocks[root.selectedIndex].id)
      return true
    }
    if (event.key === Qt.Key_Delete) {
      root.showAll()
      return true
    }
    if (event.key === Qt.Key_Space) {
      root.setStyle(root.resetStyle === "relative" ? "absolute" : "relative")
      return true
    }
    if (event.key === Qt.Key_A) {
      root.toggleAmounts()
      return true
    }
    return false
  }

  implicitWidth: body.implicitWidth
  implicitHeight: body.implicitHeight

  Component.onCompleted: root.forceActiveFocus()

  Column {
    id: body
    width: root.contentWidth
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Usage blocks"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.weight: Font.Medium
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Go limits each model over three blocks. Hide one to leave it off the tile. Enter toggles the selected block, Space switches the reset style, A switches the money line, and Delete shows all three again."
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.blocks

      BorderSurface {
        id: blockRow
        required property var modelData
        required property int index
        width: body.width
        height: Style.space(46)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(9)

          Column {
            width: blockRow.width - Style.space(80)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(modelData.label)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(modelData.note)
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.isHidden(modelData.id) ? "HIDDEN" : "SHOWN"
            color: root.foreground
            opacity: root.isHidden(modelData.id) ? 0.45 : 0.75
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 2)
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.toggle(modelData.id)
        }
      }
    }

    BorderSurface {
      width: body.width
      height: Style.space(46)
      radius: root.cornerRadius
      color: "transparent"
      borderSpec: Border.none()

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(9)

        Column {
          width: parent.width - Style.space(80)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Reset style"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.resetStyle === "absolute"
              ? "Shows the calendar day instead of a countdown"
              : "Shows how long until the block frees up"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.resetStyle === "absolute" ? "DAY" : "TIME"
          color: root.foreground
          opacity: 0.75
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setStyle(root.resetStyle === "relative" ? "absolute" : "relative")
      }
    }

    BorderSurface {
      width: body.width
      height: Style.space(46)
      radius: root.cornerRadius
      color: "transparent"
      borderSpec: Border.none()

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(9)

        Column {
          width: parent.width - Style.space(80)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Money line"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Spent of the block, under each bar"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.showAmounts ? "ON" : "OFF"
          color: root.foreground
          opacity: root.showAmounts ? 0.75 : 0.45
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleAmounts()
      }
    }
  }
}
