import QtQuick
import qs.Commons
import "../_kit"
import "mlb.js" as Mlb

// The postseason between games: a card per series in the round being played,
// then earlier rounds' results as the room allows. Once the World Series is
// decided the champion leads instead of the cards.
//
// A card is the two clubs, a pip for each win the series needs, and the
// series score between them. Under that, the next game (number, day, time,
// channel), then the probable pitchers and the last result. A finished series
// shows its result and where the winner plays next. A short tile drops the
// third line, then the second, and then each card is a single row.
Item {
  id: series

  property var post: ({})
  property color ink: Color.menu.text
  property color mark: Color.urgent
  property string fontFamily: Style.font.menuFamily

  signal openGame(string url)

  readonly property var rows: (series.post && series.post.series) || []
  readonly property var groups: (series.post && series.post.earlier) || []
  readonly property var champion: series.post && series.post.champion ? series.post.champion : null
  readonly property int cards: series.champion ? 0 : series.rows.length

  readonly property int gap: Style.space(4)
  readonly property int padV: Style.space(5)
  readonly property int padH: Style.space(8)
  readonly property int lineH: Style.font.caption + Style.space(4)
  readonly property int resultH: Style.font.caption + Style.space(5)
  readonly property int groupTitleH: Style.font.caption + Style.space(4)
  readonly property int groupGap: Style.space(6)
  readonly property int heroLogo: Style.space(44)
  readonly property int heroH: series.champion
    ? series.heroLogo + Style.space(6) + Style.font.heading + Style.space(4) + series.lineH * 2
    : 0
  readonly property var groupSizes: {
    var out = []
    for (var i = 0; i < series.groups.length; i++) {
      var members = series.groups[i] && series.groups[i].series
      out.push(members ? members.length : 0)
    }
    return out
  }
  readonly property var plan: Mlb.seriesLayout(series.cards, series.groupSizes, body.height, {
    gap: series.gap,
    padV: series.padV,
    club: Style.font.title + Style.space(8),
    clubMax: Style.font.title + Style.space(14),
    line: series.lineH,
    thin: Style.font.caption + Style.space(12),
    hero: series.heroH,
    groupGap: series.groupGap,
    groupTitle: series.groupTitleH,
    result: series.resultH
  })
  readonly property int clubH: series.plan.club
  readonly property int abbrPx: Math.max(Style.font.body, Math.round(series.clubH * 0.55))
  readonly property int scorePx: Math.max(Style.font.title, Math.round(series.clubH * 0.68))
  readonly property int pip: Math.max(Style.space(6), Math.round(series.clubH * 0.25))
  readonly property int pipGap: Math.max(2, Math.round(series.pip * 0.5))
  readonly property int mostPips: {
    var most = 0
    for (var i = 0; i < series.rows.length; i++) most = Math.max(most, Number(series.rows[i] && series.rows[i].need) || 0)
    return most
  }
  // Pips only when every card has room for them beside the series score.
  // A narrow tile keeps the score and drops the pips on every card alike.
  readonly property bool showPips: {
    var inner = series.width - series.padH * 2
    var side = series.clubH - Style.space(4) + Style.space(6) + abbrGauge.implicitWidth
    var pips = series.mostPips > 0 ? Style.space(6) + series.mostPips * series.pip + (series.mostPips - 1) * series.pipGap : 0
    return 2 * (side + pips) + scoreGauge.implicitWidth + Style.space(8) <= inner
  }

  function logoSource(id) {
    var n = Number(id)
    if (!isFinite(n) || n <= 0) return ""
    return Qt.resolvedUrl("logos/" + Math.round(n) + ".png")
  }

  // Every club name takes the width of the widest, so the pips and the
  // series score line up from card to card.
  Text { id: abbrGauge; visible: false; text: "WWW"; font.family: series.fontFamily; font.pixelSize: series.abbrPx; font.weight: Font.DemiBold }
  Text { id: scoreGauge; visible: false; text: "0–0"; font.family: series.fontFamily; font.pixelSize: series.scorePx; font.weight: Font.DemiBold }
  Text { id: thinGauge; visible: false; text: "WWW"; font.family: series.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }
  Text { id: resultGauge; visible: false; text: "WWW"; font.family: series.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.DemiBold }

  // One pip per win the series needs, filled from the club's name toward
  // the middle as it wins.
  component Pips: Row {
    id: pips
    property int need: 0
    property int wins: 0
    property bool mirror: false
    property real size: series.pip
    layoutDirection: pips.mirror ? Qt.RightToLeft : Qt.LeftToRight
    spacing: series.pipGap

    Repeater {
      model: pips.need
      Rectangle {
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        width: pips.size
        height: pips.size
        radius: width / 2
        antialiasing: true
        color: index < pips.wins ? series.ink : "transparent"
        border.color: series.ink
        border.width: Math.max(1, Style.space(1))
        opacity: index < pips.wins ? 1 : 0.35
      }
    }
  }

  // A club's logo, or a faint ring for a seed not decided yet.
  component Logo: Item {
    id: logo
    property int clubId: 0
    property int size: Style.space(16)
    width: logo.size
    height: logo.size

    Image {
      anchors.fill: parent
      visible: logo.clubId > 0
      source: series.logoSource(logo.clubId)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      sourceSize.width: width * 2
      sourceSize.height: height * 2
    }

    Rectangle {
      anchors.fill: parent
      visible: logo.clubId <= 0
      radius: width / 2
      color: "transparent"
      border.color: series.ink
      border.width: Math.max(1, Style.space(1))
      opacity: 0.3
    }
  }

  // Logo, name, and pips for one side of a card. The right side mirrors.
  component ClubSide: Row {
    id: side
    property var club: ({})
    property int need: 0
    property bool mirror: false
    property bool strong: false
    property bool faded: false
    layoutDirection: side.mirror ? Qt.RightToLeft : Qt.LeftToRight
    spacing: Style.space(6)
    opacity: side.faded ? 0.4 : 1

    Logo {
      anchors.verticalCenter: parent.verticalCenter
      clubId: Number(side.club && side.club.id) || 0
      size: series.clubH - Style.space(4)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: abbrGauge.implicitWidth
      horizontalAlignment: side.mirror ? Text.AlignRight : Text.AlignLeft
      textFormat: Text.PlainText
      text: String((side.club && side.club.abbr) || "")
      color: series.ink
      opacity: side.strong ? 1 : 0.8
      font.family: series.fontFamily
      font.pixelSize: series.abbrPx
      font.weight: side.strong ? Font.DemiBold : Font.Medium
    }

    Pips {
      visible: series.showPips
      anchors.verticalCenter: parent.verticalCenter
      need: side.need
      wins: Number(side.club && side.club.wins) || 0
      mirror: side.mirror
    }
  }

  // AL / NL, or ALCS / NLDS when the leagues are in different rounds.
  component Tag: Item {
    id: tag
    property string label: ""
    visible: tag.label.length > 0
    width: tag.visible ? tagText.implicitWidth + Style.space(8) : 0
    height: Style.font.caption + Style.space(3)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: "transparent"
      border.color: series.ink
      border.width: Math.max(1, Style.space(1))
      opacity: 0.35
    }

    Text {
      id: tagText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tag.label
      color: series.ink
      opacity: 0.7
      font.family: series.fontFamily
      font.pixelSize: Style.font.caption - 1
      font.weight: Font.DemiBold
      font.letterSpacing: 0.5
    }
  }

  // A caption line with words on the left and a value on the right. The
  // right keeps its width; the left shortens.
  component SplitLine: Item {
    id: split
    property string leftText: ""
    property string rightText: ""
    property color leftColor: series.ink
    property real leftOpacity: 1
    property bool leftStrong: false
    property real rightOpacity: 0.6
    property real indent: 0
    height: series.lineH

    Text {
      anchors.left: parent.left
      anchors.leftMargin: split.indent
      anchors.right: splitRight.visible ? splitRight.left : parent.right
      anchors.rightMargin: splitRight.visible ? Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: split.leftText
      color: split.leftColor
      opacity: split.leftOpacity
      font.family: series.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: split.leftStrong ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }

    Text {
      id: splitRight
      visible: text.length > 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: split.rightText
      color: series.ink
      opacity: split.rightOpacity
      font.family: series.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
    }
  }

  component SeriesCard: Item {
    id: card
    property var row: ({})
    readonly property var words: Mlb.seriesCard(card.row)
    readonly property var leftClub: (card.row && card.row.left) || ({})
    readonly property var rightClub: (card.row && card.row.right) || ({})
    readonly property int need: Number(card.row && card.row.need) || 0

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: Qt.rgba(series.ink.r, series.ink.g, series.ink.b, cardMouse.containsMouse ? 0.12 : 0.06)
    }

    // A stripe down the left edge while a game in this series is on today.
    Rectangle {
      visible: card.words.hot
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.topMargin: Style.space(5)
      anchors.bottomMargin: Style.space(5)
      width: Math.max(2, Style.space(2))
      radius: width / 2
      color: series.mark
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: series.openGame(String((card.row && card.row.gameday) || ""))
    }

    Column {
      visible: series.plan.lines > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: series.padH
      anchors.rightMargin: series.padH
      anchors.verticalCenter: parent.verticalCenter

      Item {
        width: parent.width
        height: series.clubH

        ClubSide {
          id: leftSide
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          club: card.leftClub
          need: card.need
          strong: card.row.leader === "left"
          faded: card.row.winner === "right"
        }

        // Between the two sides, shrinking before it would touch the pips.
        Text {
          anchors.left: leftSide.right
          anchors.right: rightSide.left
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          height: parent.height
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: Style.font.caption
          textFormat: Text.PlainText
          text: Mlb.seriesScore(card.row)
          color: series.ink
          opacity: text === "vs" ? 0.45 : 1
          font.family: series.fontFamily
          font.pixelSize: text === "vs" ? Style.font.caption : series.scorePx
          font.weight: text === "vs" ? Font.Medium : Font.DemiBold
        }

        ClubSide {
          id: rightSide
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          mirror: true
          club: card.rightClub
          need: card.need
          strong: card.row.leader === "right"
          faded: card.row.winner === "left"
        }
      }

      Item {
        width: parent.width
        height: series.lineH

        Tag {
          id: cardTag
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          label: String((card.row && card.row.tag) || "")
        }

        SplitLine {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          indent: cardTag.visible ? cardTag.width + Style.space(6) : 0
          leftText: card.words.status
          rightText: card.words.statusSide
          leftColor: card.words.hot ? series.mark : series.ink
          leftStrong: card.words.hot || !!card.row.over
          rightOpacity: card.row.over ? 0.55 : 0.75
        }
      }

      SplitLine {
        visible: series.plan.lines > 1
        width: parent.width
        indent: cardTag.visible ? cardTag.width + Style.space(6) : 0
        leftText: card.words.detail
        rightText: card.words.detailSide
        leftOpacity: card.words.detail === "Pitchers TBD" ? 0.4 : 0.65
        rightOpacity: 0.55
      }
    }

    // One row: logo NYY 2–1 TB logo ············ Tue 6:08 PM
    Item {
      visible: series.plan.lines === 0
      anchors.fill: parent
      anchors.leftMargin: series.padH
      anchors.rightMargin: series.padH

      Row {
        id: thinClubs
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Logo {
          anchors.verticalCenter: parent.verticalCenter
          clubId: Number(card.leftClub.id) || 0
          size: Style.font.caption + Style.space(3)
          opacity: card.row.winner === "right" ? 0.4 : 1
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: thinGauge.implicitWidth
          textFormat: Text.PlainText
          text: String(card.leftClub.abbr || "")
          color: series.ink
          opacity: card.row.winner === "right" ? 0.4 : 1
          font.family: series.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: card.row.leader === "left" ? Font.DemiBold : Font.Medium
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Mlb.seriesScore(card.row)
          color: series.ink
          opacity: text === "vs" ? 0.45 : 1
          font.family: series.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: thinGauge.implicitWidth
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: String(card.rightClub.abbr || "")
          color: series.ink
          opacity: card.row.winner === "left" ? 0.4 : 1
          font.family: series.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: card.row.leader === "right" ? Font.DemiBold : Font.Medium
        }
        Logo {
          anchors.verticalCenter: parent.verticalCenter
          clubId: Number(card.rightClub.id) || 0
          size: Style.font.caption + Style.space(3)
          opacity: card.row.winner === "left" ? 0.4 : 1
        }
      }

      Text {
        anchors.left: thinClubs.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: card.words.brief
        color: card.words.hot ? series.mark : series.ink
        opacity: card.words.hot ? 1 : 0.7
        font.family: series.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: card.words.hot ? Font.DemiBold : Font.Medium
        elide: Text.ElideRight
      }
    }
  }

  // logo CWS 2–0 HOU: one finished series in an earlier round.
  component Result: Item {
    id: result
    property var row: ({})
    readonly property var parts: Mlb.seriesResult(result.row)
    height: series.resultH

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: Qt.rgba(series.ink.r, series.ink.g, series.ink.b, 0.08)
      visible: resultMouse.containsMouse
    }

    MouseArea {
      id: resultMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: series.openGame(String((result.row && result.row.gameday) || ""))
    }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(5)

      Logo {
        anchors.verticalCenter: parent.verticalCenter
        clubId: Number(result.parts.won.id) || 0
        size: Style.font.caption + Style.space(4)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: resultGauge.implicitWidth
        textFormat: Text.PlainText
        text: String(result.parts.won.abbr || "")
        color: series.ink
        font.family: series.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: result.parts.score
        color: series.ink
        opacity: 0.8
        font.family: series.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(result.parts.lost.abbr || "")
        color: series.ink
        opacity: 0.45
        font.family: series.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  WidgetHeader {
    id: header
    anchors.top: parent.top
    title: String((series.post && series.post.title) || "Postseason").toUpperCase()
    trailing: String((series.post && series.post.trailing) || "")
    dotColor: series.mark
    fontFamily: series.fontFamily
    foreground: series.ink
  }

  Item {
    id: body
    anchors.top: header.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom

    Column {
      id: stack
      width: parent.width
      y: Math.max(0, Math.round((parent.height - height) / 2))
      spacing: 0

      // The champion: logo, club, title, and who they beat.
      Item {
        visible: !!series.champion
        width: parent.width
        height: visible ? series.heroH : 0

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: series.openGame(String((series.champion && series.champion.gameday) || ""))
        }

        Column {
          width: parent.width
          spacing: 0

          Logo {
            anchors.horizontalCenter: parent.horizontalCenter
            clubId: Number(series.champion && series.champion.id) || 0
            size: series.heroLogo
          }
          Item { width: 1; height: Style.space(6) }
          Text {
            width: parent.width
            height: Style.font.heading + Style.space(4)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String((series.champion && series.champion.club) || "")
            color: series.ink
            font.family: series.fontFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            height: series.lineH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: "WORLD SERIES CHAMPIONS"
            color: series.mark
            font.family: series.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            height: series.lineH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String((series.champion && series.champion.line) || "")
            color: series.ink
            opacity: 0.65
            font.family: series.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Column {
        width: parent.width
        spacing: series.gap

        Repeater {
          model: series.cards
          SeriesCard {
            required property int index
            row: series.rows[index] || ({})
            width: stack.width
            height: series.plan.cardH
          }
        }
      }

      // Earlier rounds, newest first: a titled rule, then the results two
      // to a line, the American League on the left.
      Repeater {
        model: Math.min(series.plan.groups, series.groups.length)

        Column {
          id: group
          required property int index
          readonly property var members: (series.groups[index] && series.groups[index].series) || []
          width: stack.width
          topPadding: index > 0 || series.cards > 0 || series.champion ? series.groupGap : 0

          Item {
            width: parent.width
            height: series.groupTitleH

            Text {
              id: groupTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String((series.groups[group.index] && series.groups[group.index].title) || "").toUpperCase()
              color: series.ink
              opacity: 0.5
              font.family: series.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: 1
            }

            Rectangle {
              anchors.left: groupTitle.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Math.max(1, Style.space(1))
              color: series.ink
              opacity: 0.15
            }
          }

          Grid {
            width: parent.width
            flow: Grid.TopToBottom
            rows: Math.max(1, Math.ceil(group.members.length / 2))
            columnSpacing: Style.space(8)

            Repeater {
              model: group.members.length
              Result {
                required property int index
                row: group.members[index] || ({})
                width: (stack.width - Style.space(8)) / 2
              }
            }
          }
        }
      }
    }
  }
}
