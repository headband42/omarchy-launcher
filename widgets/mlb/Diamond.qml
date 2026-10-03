import QtQuick
import qs.Commons

// Three bases as squares turned 45°, second on top, with a little air between
// them so the shape still reads at a few pixels. Filled when occupied. The
// slate cards and the single-game view both draw it.
Item {
  id: diamond

  property var bases: []
  property real base: Style.space(6)
  property real air: Math.max(1.5, diamond.base * 0.3)
  property color ink: Color.menu.text
  // An empty base is a faint tile under its outline, so it reads as a base
  // and not a gap.
  property real emptyFill: 0

  // Centre-to-centre step along each axis between second and a corner base.
  readonly property real step: (diamond.base + diamond.air) / Math.sqrt(2)
  readonly property real half: diamond.base / Math.sqrt(2)
  width: diamond.step * 2 + diamond.half * 2
  height: diamond.step + diamond.half * 2

  Repeater {
    // [first, second, third] as steps from the left and top edges.
    model: [
      { at: 0, x: 2, y: 1 },
      { at: 1, x: 1, y: 0 },
      { at: 2, x: 0, y: 1 }
    ]
    Item {
      id: bag
      required property var modelData
      readonly property bool taken: !!diamond.bases[bag.modelData.at]
      x: diamond.half + diamond.step * bag.modelData.x - width / 2
      y: diamond.half + diamond.step * bag.modelData.y - height / 2
      width: diamond.base
      height: diamond.base
      rotation: 45
      antialiasing: true

      Rectangle {
        anchors.fill: parent
        antialiasing: true
        visible: !bag.taken && diamond.emptyFill > 0
        color: Qt.rgba(diamond.ink.r, diamond.ink.g, diamond.ink.b, diamond.emptyFill)
      }

      Rectangle {
        anchors.fill: parent
        antialiasing: true
        color: bag.taken ? diamond.ink : "transparent"
        border.color: diamond.ink
        border.width: Math.max(1, Style.space(1))
        opacity: bag.taken ? 1 : 0.6
      }
    }
  }
}
