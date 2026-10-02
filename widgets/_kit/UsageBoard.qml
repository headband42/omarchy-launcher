import QtQuick
import qs.Commons
import "usage.js" as Usage

// The body of a plan tile (OpenCode Go, Claude): a header, the block closest
// to its ceiling as one big number, a UsageMeter per block, and a footer.
// With no rows it shows `emptyHeadline` and `emptyBody` instead.
//
//   UsageBoard {
//     anchors.fill: parent
//     title: "OPENCODE GO"
//     status: "active"
//     rows: [{ label: "WEEK", percent: 6.4, over: false, detail: "$1.92 of $30 · resets in 3d 16h",
//              caption: "of this week’s block" }]
//     footer: "through Oct 25"
//     footnote: root.offline ? "updated 12m ago" : ""
//     fontFamily: root.fontFamily
//     foreground: root.foreground
//   }
//
// It draws no MouseArea, so a click falls through to the grid and opens the
// slot's Opens.
Item {
  id: board

  property string title: ""
  property string status: ""
  property var rows: []
  property string footer: ""
  property string footnote: ""
  // The numbers are old: drawn dimmer, with the footnote saying how old.
  property bool stale: false
  // Something is close to its ceiling: the header dot breathes.
  property bool busy: false
  property string emptyHeadline: ""
  property string emptyBody: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  readonly property var list: Usage.toList(board.rows)
  readonly property int worst: Usage.worstIndex(board.list)
  readonly property var headline: board.worst >= 0 ? board.list[board.worst] : null

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: board.title
      trailing: board.status
      dotColor: board.list.length && !board.stale ? headlineMeter.tint : board.foreground
      dotOpacity: board.list.length && !board.stale ? 1 : 0.35
      pulse: board.busy && !board.stale
      fontFamily: board.fontFamily
      foreground: board.foreground
    }

    // A meter that is never shown: its tint colors the headline number, and
    // its height sizes the gaps between the real ones.
    UsageMeter {
      id: headlineMeter
      visible: false
      width: parent.width
      percent: board.headline ? board.headline.percent : null
      over: !!(board.headline && board.headline.over)
      detail: "x"
      fontFamily: board.fontFamily
      foreground: board.foreground
    }

    Item {
      id: hero
      visible: board.list.length > 0
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      width: parent.width
      height: big.implicitHeight

      Text {
        id: big
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: Usage.percentText(board.headline ? board.headline.percent : null)
        color: board.headline && Usage.finite(board.headline.percent) !== null ? headlineMeter.tint : board.foreground
        font.family: board.fontFamily
        font.pixelSize: Style.font.iconLarge * 2
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
      }

      Text {
        anchors.left: big.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.baseline: big.baseline
        textFormat: Text.PlainText
        text: board.headline ? String(board.headline.caption || "") : ""
        color: board.foreground
        opacity: 0.6
        font.family: board.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Item {
      id: area
      visible: board.list.length > 0
      anchors.top: hero.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: foot.top
      anchors.bottomMargin: Style.space(6)
      width: parent.width
      opacity: board.stale ? 0.6 : 1

      // The meters share the room: the gaps grow to fill it, within reason.
      readonly property real gap: {
        var n = board.list.length
        if (n < 1) return 0
        var spare = area.height - n * headlineMeter.implicitHeight
        return Math.max(Style.space(6), Math.min(Style.space(20), spare / n))
      }

      Column {
        y: area.gap / 2
        width: parent.width
        spacing: area.gap

        Repeater {
          model: board.list

          UsageMeter {
            required property var modelData
            required property int index
            width: area.width
            label: String(modelData.label || "")
            percent: modelData.percent
            over: !!modelData.over
            detail: String(modelData.detail || "")
            emphasized: index === board.worst
            fontFamily: board.fontFamily
            foreground: board.foreground
          }
        }
      }
    }

    Item {
      id: foot
      visible: board.list.length > 0 && (board.footer.length > 0 || board.footnote.length > 0)
      anchors.bottom: parent.bottom
      width: parent.width
      height: visible ? footText.implicitHeight : 0

      Text {
        id: footText
        anchors.left: parent.left
        anchors.right: noteText.left
        anchors.rightMargin: Style.space(8)
        textFormat: Text.PlainText
        text: board.footer
        color: board.foreground
        opacity: 0.45
        font.family: board.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        id: noteText
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: board.footnote
        color: board.stale ? Color.urgent : board.foreground
        opacity: board.stale ? 0.85 : 0.45
        font.family: board.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      visible: board.list.length === 0
      anchors.centerIn: parent
      width: parent.width - Style.space(12)
      spacing: Style.space(6)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: board.emptyHeadline
        color: board.foreground
        opacity: 0.85
        font.family: board.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      Text {
        visible: text.length > 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: board.emptyBody
        color: board.foreground
        opacity: 0.55
        font.family: board.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 5
      }
    }
  }
}
