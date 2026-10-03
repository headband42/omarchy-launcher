import QtQuick
import qs.Commons
import "../_kit"
import "mlb.js" as Mlb

// The live slate: one card per game, sized to fit however many are on.
//
// Each card puts the two clubs on their own lines with the inning, bases, and
// outs beside them. As a card gets taller it adds the series (or TV) line on
// top and the count and matchup underneath, and the club lines grow. When even
// that will not fit, a card is one line, and past one column of those the
// cards wrap into two.
Item {
  id: board

  property var games: []
  property string banner: "Live"
  property color ink: Color.menu.text
  property color mark: Color.urgent
  property string fontFamily: Style.font.menuFamily

  signal openGame(string url)

  readonly property int count: board.games.length
  readonly property bool postseason: {
    for (var i = 0; i < board.count; i++) {
      if (board.games[i] && board.games[i].series) return true
    }
    return false
  }

  readonly property bool anyTop: {
    for (var i = 0; i < board.count; i++) {
      var game = board.games[i]
      if (game && (game.series || game.tv)) return true
    }
    return false
  }

  readonly property int gap: Style.space(4)
  readonly property int pad: board.columns > 1 ? Style.space(5) : Style.space(7)
  readonly property int padV: Style.space(4)
  readonly property int capH: Style.font.caption + Style.space(4)
  readonly property int minLineH: Style.font.body + Style.space(5)
  readonly property int maxLineH: Style.font.heading + Style.space(14)
  readonly property int thinH: Style.font.caption + Style.space(8)
  // Two columns only once a single column of one-line cards would not fit.
  readonly property int columns: board.count > 1 && board.count * (board.thinH + board.gap) - board.gap > list.height ? 2 : 1
  readonly property int rows: Math.max(1, Math.ceil(board.count / board.columns))
  readonly property real cellW: Math.max(0, (list.width - (board.columns - 1) * board.gap) / board.columns)
  readonly property real cellH: Math.max(0, (list.height - (board.rows - 1) * board.gap) / board.rows)
  readonly property real spare: board.cellH - board.padV * 2 - board.minLineH * 2
  readonly property bool thin: board.columns > 1 || board.spare < 0
  readonly property bool showTop: !board.thin && board.anyTop && board.spare >= board.capH
  readonly property bool showMatchup: !board.thin && board.spare - (board.showTop ? board.capH : 0) >= board.capH
  readonly property int lineH: {
    var room = board.spare + board.minLineH * 2 - (board.showTop ? board.capH : 0) - (board.showMatchup ? board.capH : 0)
    return Math.max(board.minLineH, Math.min(board.maxLineH, Math.floor(room * 0.85 / 2)))
  }
  readonly property int clubPx: Math.max(Style.font.body, Math.round(board.lineH * 0.6))
  readonly property bool lineLogos: board.cellW >= Style.space(150)
  readonly property string scoreDigits: {
    for (var i = 0; i < board.count; i++) {
      var game = board.games[i] || {}
      if (Number(game.away && game.away.score) >= 10 || Number(game.home && game.home.score) >= 10) return "00"
    }
    return "0"
  }

  function logoSource(id) {
    var n = Number(id)
    if (!isFinite(n) || n <= 0) return ""
    return Qt.resolvedUrl("logos/" + Math.round(n) + ".png")
  }

  function dimmed(game, side) {
    return !!(game && game.leader && game.leader !== side)
  }

  // ▲ 6 while the visitors bat, ▼ 6 for the home half, Mid 6 / End 6 between.
  function inningText(game) {
    if (!game) return ""
    if (game.note) return String(game.note)
    var n = Number(game.inning) || 0
    if (!n) return String(game.status || "")
    if (game.half === "top") return "▲ " + n
    if (game.half === "bottom") return "▼ " + n
    if (game.half === "middle") return "Mid " + n
    if (game.half === "end") return "End " + n
    return String(game.status || "")
  }

  // ▲6 / ▼6 for a one-line card. Between halves it points at the half up next.
  function shortInning(game) {
    if (!game) return ""
    var n = Number(game.inning) || 0
    if (!n) return ""
    if (game.half === "top") return "▲" + n
    if (game.half === "bottom" || game.half === "middle") return "▼" + n
    if (game.half === "end") return "▲" + (n + 1)
    return ""
  }

  function atBat(game) {
    return !!game && !game.note && (game.half === "top" || game.half === "bottom")
  }

  function matchup(game) {
    if (!game) return ""
    var bits = []
    if (game.balls !== null && game.balls !== undefined && game.strikes !== null && game.strikes !== undefined)
      bits.push(game.balls + "-" + game.strikes)
    if (game.batterShort && game.pitcherShort) bits.push(game.batterShort + " vs " + game.pitcherShort)
    else if (game.batterShort) bits.push(game.batterShort + " batting")
    return bits.join(" · ")
  }

  FontMetrics {
    id: captionMetrics
    font.family: board.fontFamily
    font.pixelSize: Style.font.caption
  }

  // The longest series line that fits in `room`.
  function seriesFor(game, room) {
    var lines = Mlb.seriesLines(game)
    for (var i = 0; i < lines.length; i++) {
      if (captionMetrics.advanceWidth(lines[i]) <= room) return lines[i]
    }
    return lines.length ? lines[lines.length - 1] : ""
  }

  // Monospace gauges so every club's score lines up under the one above it.
  Text { id: abbrGauge; visible: false; text: "WWW"; font.family: board.fontFamily; font.pixelSize: board.clubPx; font.weight: Font.Medium }
  Text { id: scoreGauge; visible: false; text: board.scoreDigits; font.family: board.fontFamily; font.pixelSize: board.clubPx + 1; font.weight: Font.DemiBold }
  Text { id: thinAbbrGauge; visible: false; text: "WWW"; font.family: board.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.Medium }
  Text { id: thinScoreGauge; visible: false; text: board.scoreDigits; font.family: board.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }

  component Outs: Row {
    id: outs
    property int filled: 0
    property real pip: Style.space(4)
    spacing: Style.space(2)

    Repeater {
      model: 3
      Rectangle {
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        width: outs.pip
        height: outs.pip
        radius: width / 2
        color: index < outs.filled ? board.ink : "transparent"
        border.color: board.ink
        border.width: Math.max(1, Style.space(1))
        opacity: index < outs.filled ? 1 : 0.45
      }
    }
  }

  // Logo, abbreviation, and score for one club on its own line.
  component ClubLine: Row {
    id: clubLine
    property var club: ({})
    property bool dim: false
    height: board.lineH
    spacing: Style.space(6)
    opacity: clubLine.dim ? 0.55 : 1

    Image {
      anchors.verticalCenter: parent.verticalCenter
      width: board.lineH - Style.space(3)
      height: width
      source: board.logoSource(clubLine.club && clubLine.club.id)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      sourceSize.width: width * 2
      sourceSize.height: height * 2
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: abbrGauge.implicitWidth
      textFormat: Text.PlainText
      text: String((clubLine.club && clubLine.club.abbr) || "")
      color: board.ink
      font.family: board.fontFamily
      font.pixelSize: board.clubPx
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: scoreGauge.implicitWidth
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: String((clubLine.club && clubLine.club.score) || "0")
      color: board.ink
      font.family: board.fontFamily
      font.pixelSize: board.clubPx + 1
      font.weight: Font.DemiBold
    }
  }

  // One club in a one-line card.
  component ThinClub: Row {
    id: thin
    property var club: ({})
    property bool dim: false
    spacing: Style.space(4)
    opacity: thin.dim ? 0.55 : 1

    Image {
      visible: board.lineLogos
      anchors.verticalCenter: parent.verticalCenter
      width: Style.font.caption + Style.space(2)
      height: width
      source: board.lineLogos ? board.logoSource(thin.club && thin.club.id) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      sourceSize.width: width * 2
      sourceSize.height: height * 2
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: thinAbbrGauge.implicitWidth
      textFormat: Text.PlainText
      text: String((thin.club && thin.club.abbr) || "")
      color: board.ink
      font.family: board.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: thinScoreGauge.implicitWidth
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: String((thin.club && thin.club.score) || "0")
      color: board.ink
      font.family: board.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
    }
  }

  component GameCard: Item {
    id: card
    property var game: ({})
    readonly property var away: (card.game && card.game.away) || ({})
    readonly property var home: (card.game && card.game.home) || ({})

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: Qt.rgba(board.ink.r, board.ink.g, board.ink.b, cardMouse.containsMouse ? 0.12 : 0.06)
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: board.openGame(String(card.game.gameday || ""))
    }

    // line: BOS 1  NYY 4 ······ ▼ 6
    Item {
      visible: board.thin
      anchors.fill: parent
      anchors.leftMargin: board.pad
      anchors.rightMargin: board.pad

      Row {
        id: thinClubs
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        ThinClub { club: card.away; dim: board.dimmed(card.game, "away") }
        ThinClub { club: card.home; dim: board.dimmed(card.game, "home") }
      }

      // The full inning when it fits, else ▲6 / ▼6, else nothing at all.
      Item {
        anchors.left: thinClubs.right
        anchors.leftMargin: Style.space(4)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: thinInning.implicitHeight

        Text { id: fullGauge; visible: false; text: board.inningText(card.game); font: thinInning.font }

        Text {
          id: thinInning
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: fullGauge.implicitWidth <= parent.width ? board.inningText(card.game) : board.shortInning(card.game)
          visible: implicitWidth <= parent.width
          color: board.ink
          opacity: 0.75
          font.family: board.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
      }
    }

    // stack and roomy
    Column {
      visible: !board.thin
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: board.pad
      anchors.rightMargin: board.pad
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Item {
        visible: board.showTop
        width: parent.width
        height: board.capH

        // The series score matters more than the channel. TV only shows when
        // the full series line fits beside it; otherwise the series line takes
        // the row and shortens itself to fit.
        Text {
          id: tvText
          visible: text.length > 0
            && captionMetrics.advanceWidth(String(card.game.series || "")) + Style.space(8) + implicitWidth <= parent.width
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(card.game.tv || "")
          color: board.ink
          opacity: 0.5
          font.family: board.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: seriesText
          anchors.left: parent.left
          anchors.right: tvText.visible ? tvText.left : parent.right
          anchors.rightMargin: tvText.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: board.seriesFor(card.game, parent.width - (tvText.visible ? tvText.implicitWidth + Style.space(8) : 0))
          color: board.ink
          opacity: 0.6
          font.family: board.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Item {
        width: parent.width
        height: board.lineH * 2

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          ClubLine { club: card.away; dim: board.dimmed(card.game, "away") }
          ClubLine { club: card.home; dim: board.dimmed(card.game, "home") }
        }

        // Inning beside the visitors, bases and outs beside the home club.
        Text {
          anchors.right: parent.right
          y: (board.lineH - height) / 2
          textFormat: Text.PlainText
          text: board.inningText(card.game)
          color: board.ink
          font.family: board.fontFamily
          font.pixelSize: Math.max(Style.font.caption, Math.round(board.clubPx * 0.75))
          font.weight: Font.DemiBold
        }

        Row {
          visible: board.atBat(card.game)
          anchors.right: parent.right
          y: board.lineH + (board.lineH - height) / 2
          spacing: Style.space(6)

          Diamond {
            anchors.verticalCenter: parent.verticalCenter
            ink: board.ink
            bases: (card.game && card.game.bases) || []
            base: Math.max(Style.space(5), Math.round(board.lineH * 0.34))
          }

          Outs {
            anchors.verticalCenter: parent.verticalCenter
            filled: Math.max(0, Math.min(3, Number(card.game.outs) || 0))
            pip: Math.max(Style.space(4), Math.round(board.lineH * 0.26))
          }
        }
      }

      Text {
        visible: board.showMatchup
        width: parent.width
        textFormat: Text.PlainText
        text: board.matchup(card.game)
        color: board.ink
        opacity: 0.6
        font.family: board.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  WidgetHeader {
    id: header
    anchors.top: parent.top
    title: board.banner === "Live" && board.postseason ? "POSTSEASON" : String(board.banner || "Live").toUpperCase()
    trailing: board.count + " live"
    dotColor: board.mark
    pulse: true
    fontFamily: board.fontFamily
    foreground: board.ink
  }

  Grid {
    id: list
    anchors.top: header.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    // Top to bottom with only `rows` set, so the Grid works out the columns
    // and never sees more cards than cells while the count changes.
    flow: Grid.TopToBottom
    rows: board.rows
    rowSpacing: board.gap
    columnSpacing: board.gap

    Repeater {
      model: board.count
      GameCard {
        required property int index
        game: board.games[index] || ({})
        width: board.cellW
        height: board.cellH
      }
    }
  }
}
