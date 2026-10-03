import QtQuick
import qs.Commons

// The inning-by-inning box: a row of inning numbers, a row per club, and the
// totals past a hairline. The innings share what the club names and the
// totals leave, and `fits` is false once a column is too narrow to read.
//
// `framed` sets it on a card with the inning being played (`current`) lit.
// The post-game view leaves it bare, where the standings need the height.
Item {
  id: box

  // Header first, then away and home: { header, abbr, cells, r, h, e, strong }.
  property var rows: []
  property int slots: 0
  property int current: -1
  property bool framed: false
  property int rowH: Style.font.caption + Style.space(3)
  property real minCell: Style.space(8)
  property color ink: Color.menu.text
  property string fontFamily: Style.font.menuFamily

  readonly property int padH: box.framed ? Style.space(6) : 0
  readonly property int padV: box.framed ? Style.space(3) : 0
  readonly property int nameW: nameGauge.implicitWidth + Style.space(5)
  readonly property int statW: statGauge.implicitWidth + Style.space(4)
  // Between the last inning and R, with the hairline in the middle.
  readonly property int ruleW: Style.space(7)
  readonly property real cellW: {
    if (box.slots < 1) return 0
    var room = box.width - box.padH * 2 - box.nameW - box.ruleW - box.statW * 3
    return Math.max(0, Math.floor(room / box.slots))
  }
  readonly property bool fits: box.cellW >= box.minCell
  readonly property real innerH: box.rows.length * box.rowH

  implicitHeight: box.innerH + box.padV * 2

  Text { id: nameGauge; visible: false; text: "WWW"; font.family: box.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
  Text { id: statGauge; visible: false; text: "00"; font.family: box.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }

  Rectangle {
    visible: box.framed
    anchors.fill: parent
    radius: Style.space(6)
    color: Qt.rgba(box.ink.r, box.ink.g, box.ink.b, 0.06)
  }

  Rectangle {
    visible: box.framed && box.current >= 0 && box.current < box.slots
    x: box.padH + box.nameW + box.current * box.cellW
    y: box.padV
    width: box.cellW
    height: box.innerH
    radius: Style.space(3)
    color: Qt.rgba(box.ink.r, box.ink.g, box.ink.b, 0.09)
  }

  // The totals sit at the right edge, so the hairline splits whatever gap
  // the rounded-down innings leave.
  Rectangle {
    x: Math.round((box.padH + box.nameW + box.slots * box.cellW + box.width - box.padH - box.statW * 3) / 2)
    y: box.padV + Style.space(2)
    width: Math.max(1, Style.space(1))
    height: Math.max(0, box.innerH - Style.space(4))
    color: box.ink
    opacity: 0.16
  }

  Column {
    x: box.padH
    y: box.padV
    width: box.width - box.padH * 2

    Repeater {
      model: box.rows

      Item {
        id: line
        required property var modelData
        readonly property var row: line.modelData
        width: parent.width
        height: box.rowH

        Text {
          width: box.nameW
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: String(line.row.abbr || "")
          color: box.ink
          font.family: box.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: line.row.strong ? Font.DemiBold : Font.Medium
          elide: Text.ElideRight
        }

        Repeater {
          model: box.slots

          Text {
            required property int index
            readonly property string value: {
              var cells = line.row.cells || []
              var cell = index < cells.length ? cells[index] : undefined
              return cell === undefined || cell === null ? "" : String(cell)
            }
            readonly property bool lit: box.framed && index === box.current
            x: box.nameW + index * box.cellW
            width: box.cellW
            height: line.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: value
            color: box.ink
            // Runs stand out from the zeros around them.
            opacity: line.row.header ? (lit ? 0.9 : 0.4) : (value === "0" ? 0.45 : 1)
            font.family: box.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: line.row.header ? (lit ? Font.DemiBold : Font.Normal)
              : (value !== "0" && value !== "" ? Font.DemiBold : Font.Normal)
          }
        }

        Row {
          anchors.right: parent.right
          height: parent.height

          Text {
            width: box.statW
            height: line.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String(line.row.r || "")
            color: box.ink
            opacity: line.row.header ? 0.4 : 1
            font.family: box.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: line.row.header ? Font.Normal : Font.Bold
          }

          Text {
            width: box.statW
            height: line.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String(line.row.h || "")
            color: box.ink
            opacity: line.row.header ? 0.4 : 0.7
            font.family: box.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: box.statW
            height: line.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String(line.row.e || "")
            color: box.ink
            opacity: line.row.header ? 0.4 : 0.7
            font.family: box.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
