import QtQuick
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/system.js" as Sys

// Whether temperatures are colored by how hot they run, and whether the
// hardware specs sit under the meters. Both are on by default, and turning
// both back on stores an empty object.
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

  readonly property var opts: Sys.options(root.settings)
  readonly property int rowCount: 2

  implicitWidth: Style.space(360)
  implicitHeight: body.implicitHeight

  function commit(next) {
    root.settings = Sys.storedOptions(next)
    root.forceActiveFocus()
  }

  function activate(index) {
    root.selectedIndex = index
    if (index === 0) root.commit({ tempColor: !root.opts.tempColor, specs: root.opts.specs })
    else root.commit({ tempColor: root.opts.tempColor, specs: !root.opts.specs })
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Up) {
      root.selectedIndex = (root.selectedIndex - 1 + root.rowCount) % root.rowCount
      return true
    }
    if (event.key === Qt.Key_Down) {
      root.selectedIndex = (root.selectedIndex + 1) % root.rowCount
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activate(root.selectedIndex)
      return true
    }
    if (event.key === Qt.Key_Delete) {
      root.commit({ tempColor: true, specs: true })
      return true
    }
    return false
  }

  Component.onCompleted: root.forceActiveFocus()

  Column {
    id: body
    width: parent.width
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      bottomPadding: Style.space(6)
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Enter or Space switches a row. Delete turns both back on."
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    OptionRow {
      width: body.width
      selected: root.selectedIndex === 0
      title: "Temperature colors"
      note: root.opts.tempColor ? "Blue when cool, through green and yellow, to red at 100°C" : "Temperatures in the text color"
      tag: root.opts.tempColor ? "on" : "off"
      lit: root.opts.tempColor
      hoverFill: root.hoverFill
      selectedBorder: root.borderSpec
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      foreground: root.foreground
      onHovered: root.selectedIndex = 0
      onPicked: root.activate(0)
    }

    // The scale itself, with the temperatures at its ends.
    Item {
      visible: root.opts.tempColor
      width: body.width
      height: visible ? coolLabel.implicitHeight + Style.space(6) : 0

      Text {
        id: coolLabel
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Sys.TEMP_COOL + "°C"
        color: Sys.tempColor(Sys.TEMP_COOL, root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Bold
      }

      Rectangle {
        anchors.left: coolLabel.right
        anchors.leftMargin: Style.space(8)
        anchors.right: hotLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(6)
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Sys.tempColor(Sys.TEMP_COOL, root.foreground) }
          GradientStop { position: 0.25; color: Sys.tempColor(Sys.TEMP_COOL + (Sys.TEMP_HOT - Sys.TEMP_COOL) * 0.25, root.foreground) }
          GradientStop { position: 0.5; color: Sys.tempColor(Sys.TEMP_COOL + (Sys.TEMP_HOT - Sys.TEMP_COOL) * 0.5, root.foreground) }
          GradientStop { position: 0.75; color: Sys.tempColor(Sys.TEMP_COOL + (Sys.TEMP_HOT - Sys.TEMP_COOL) * 0.75, root.foreground) }
          GradientStop { position: 1.0; color: Sys.tempColor(Sys.TEMP_HOT, root.foreground) }
        }
      }

      Text {
        id: hotLabel
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Sys.TEMP_HOT + "°C"
        color: Sys.tempColor(Sys.TEMP_HOT, root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Bold
      }
    }

    OptionRow {
      width: body.width
      selected: root.selectedIndex === 1
      title: "Hardware specs"
      note: "CPU, memory, GPU, and system drive under the meters"
      tag: root.opts.specs ? "shown" : "hidden"
      lit: root.opts.specs
      hoverFill: root.hoverFill
      selectedBorder: root.borderSpec
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      foreground: root.foreground
      onHovered: root.selectedIndex = 1
      onPicked: root.activate(1)
    }
  }
}
