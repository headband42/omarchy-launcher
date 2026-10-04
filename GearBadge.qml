import QtQuick
import QtQuick.Shapes

// Space-hint badge shaped like a gear, so the settings key reads apart from the
// round letter badges beside it. The body is about as wide as a dock badge.
Item {
  id: root

  property string text: ""
  property string fontFamily: ""
  property int textPixelSize: Math.round(root.width * 0.48)
  property color fill: "black"
  property color stroke: "white"
  property real strokeWidth: 2
  property int teeth: 8

  height: width

  readonly property string _path: {
    var n = Math.max(3, root.teeth)
    var c = root.width / 2
    var outer = c - root.strokeWidth / 2
    var body = outer * 0.8
    var pitch = 2 * Math.PI / n
    var base = pitch * 0.25
    var tip = pitch * 0.17
    function at(r, a) { return (c + r * Math.cos(a)).toFixed(2) + " " + (c + r * Math.sin(a)).toFixed(2) }
    var d = ""
    for (var i = 0; i < n; i++) {
      var a = -Math.PI / 2 + i * pitch
      d += (i === 0 ? "M " : " L ") + at(body, a - base)
      d += " L " + at(outer, a - tip)
      d += " A " + outer + " " + outer + " 0 0 1 " + at(outer, a + tip)
      d += " L " + at(body, a + base)
      d += " A " + body + " " + body + " 0 0 1 " + at(body, a + pitch - base)
    }
    return d + " Z"
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.fill
      strokeColor: root.stroke
      strokeWidth: root.strokeWidth
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root._path }
    }
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.stroke
    font.family: root.fontFamily
    font.pixelSize: root.textPixelSize
    font.weight: Font.DemiBold
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
