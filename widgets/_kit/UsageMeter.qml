import QtQuick
import qs.Commons
import "usage.js" as Usage

// One usage block: its name and percentage, a bar, and a line under it.
//
//   UsageMeter {
//     width: parent.width
//     label: "WEEK"
//     percent: meter.percent          // null draws "—" and an empty bar
//     over: meter.over
//     detail: "$1.92 of $30 · resets in 3d 16h"
//     emphasized: index === worst     // the block closest to its ceiling
//     fontFamily: root.fontFamily
//     foreground: root.foreground
//   }
//
// The bar and the number warm from the theme's accent toward its urgent
// color as the block fills, so no color is invented.
Item {
  id: meter

  property string label: ""
  property var percent: null
  property bool over: false
  property string detail: ""
  property bool emphasized: false
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  readonly property color tint: meter.ramp(Usage.toneFraction(Usage.tone(meter.percent, meter.over)))

  function ramp(fraction) {
    var from = Color.accent
    var to = Color.urgent
    var t = Math.max(0, Math.min(1, Number(fraction)))
    return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, 1)
  }

  implicitHeight: top.height + Style.space(4) + track.height + (meter.detail ? Style.space(4) + detailText.implicitHeight : 0)

  Item {
    id: top
    width: parent.width
    height: Math.max(name.implicitHeight, value.implicitHeight)

    Text {
      id: name
      anchors.left: parent.left
      anchors.right: value.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: meter.label
      color: meter.foreground
      opacity: meter.emphasized ? 0.9 : 0.6
      font.family: meter.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      font.letterSpacing: 0.8
      elide: Text.ElideRight
    }

    Text {
      id: value
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Usage.percentText(meter.percent)
      color: Usage.finite(meter.percent) === null ? meter.foreground : meter.tint
      opacity: Usage.finite(meter.percent) === null ? 0.45 : 1
      font.family: meter.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
    }
  }

  // The fill stops at the end of the track even over the limit; the number
  // says by how much.
  Rectangle {
    id: track
    anchors.top: top.bottom
    anchors.topMargin: Style.space(4)
    width: parent.width
    height: Style.space(6)
    radius: height / 2
    color: Util.alpha(meter.foreground, 0.1)

    Rectangle {
      width: Math.round(track.width * Usage.fill(meter.percent))
      height: parent.height
      radius: parent.radius
      color: meter.tint

      Behavior on width { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
    }
  }

  Text {
    id: detailText
    visible: meter.detail.length > 0
    anchors.top: track.bottom
    anchors.topMargin: Style.space(4)
    width: parent.width
    textFormat: Text.PlainText
    text: meter.detail
    color: meter.foreground
    opacity: 0.55
    font.family: meter.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    elide: Text.ElideRight
  }
}
