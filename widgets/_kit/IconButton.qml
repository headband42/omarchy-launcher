import QtQuick
import qs.Commons
import qs.Ui

// A round glyph button for a widget's rows and footer, or a pill when it has
// a label.
//
//   IconButton {
//     glyph: "󰓦"
//     busy: root.fetching          // spins, and ignores clicks
//     foreground: root.foreground
//     fontFamily: root.fontFamily
//     onClicked: root.fetch()
//   }
//
//   IconButton { glyph: ""; label: "Open lazydocker"; filled: true; ... }
//
// It accepts every click, even when it cannot act, so a dimmed button never
// falls through to the grid and launches the tile's Opens instead.
Item {
  id: button

  property string glyph: ""
  property string label: ""
  property real glyphSize: Style.font.body
  property real labelSize: Style.font.bodySmall
  property bool available: true
  property bool busy: false
  // A resting fill, so a pill reads as a button before it is hovered.
  property bool filled: false
  property color foreground: Color.menu.text
  // The glyph and fill. Defaults to the foreground.
  property color tint: button.foreground
  property string fontFamily: Style.font.menuFamily
  readonly property bool hovered: mouse.containsMouse

  signal clicked()

  height: Style.space(24)
  width: button.label.length > 0
    ? Math.ceil(content.implicitWidth) + Style.space(20)
    : height

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: button.tint
    opacity: !button.available ? (button.filled ? 0.05 : 0)
      : (mouse.containsMouse ? 0.2 : (button.filled ? 0.1 : 0))
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    OpticalGlyph {
      id: icon
      visible: button.glyph.length > 0
      width: button.label.length > 0 ? Math.ceil(button.glyphSize * 1.2) : button.width
      height: button.height
      text: button.glyph
      fontFamily: button.fontFamily
      fontSize: button.glyphSize
      color: button.tint
      opacity: !button.available ? 0.25 : (mouse.containsMouse || button.busy || button.filled ? 1 : 0.7)

      RotationAnimator on rotation {
        running: button.busy
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        onRunningChanged: if (!running) icon.rotation = 0
      }
    }

    Text {
      visible: button.label.length > 0
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: button.label
      color: button.tint
      opacity: button.available ? 1 : 0.35
      font.family: button.fontFamily
      font.pixelSize: button.labelSize
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: button.available && !button.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (button.available && !button.busy) button.clicked()
  }
}
