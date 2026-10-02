import QtQuick
import qs.Commons
import "../_kit"
import "nfl.js" as Nfl

Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  property bool loaded: false
  property bool haveScore: false

  // The club the settings panel stored. Zero means no club, and the tile
  // falls back to the week's slate rather than an empty box.
  readonly property int teamId: {
    var settings = root.tile && root.tile.settings
    var n = Number(settings && settings.teamId)
    if (!isFinite(n) || n <= 0) return 0
    return Math.round(n)
  }
  // Team colors restyle this tile only. The launcher around it stays on the
  // system theme.
  readonly property bool teamColors: {
    var settings = root.tile && root.tile.settings
    return !!(settings && settings.teamColors) && root.teamId > 0
  }

  readonly property var club: root.sample && root.sample.team ? root.sample.team : null
  // Team color tints the background only. Ink stays the menu's own text color
  // so a near-black club color can never leave the tile unreadable.
  readonly property color ink: root.foreground
  readonly property string paperHex: Nfl.colorHex(Color.menu.background)
  readonly property string inkHex: Nfl.colorHex(root.ink)
  readonly property bool darkPaper: Nfl.isDark(root.paperHex)
  // The club color that shows on this tile: Chicago's navy vanishes on a navy
  // theme, its orange does not.
  readonly property color wash: root.teamColors && root.club ? root.tintOf(root.club) : "transparent"
  readonly property string mode: String((root.sample && root.sample.mode) || "")
  readonly property bool failed: root.loaded && !!root.sample && root.sample.ok === false
  readonly property var shown: root.sample && root.sample.focus ? root.sample.focus : null
  readonly property var games: {
    var rows = root.sample && root.sample.games
    return rows && rows.length ? rows : []
  }
  readonly property var nextGame: root.sample && root.sample.next ? root.sample.next : null
  readonly property var lastGame: root.sample && root.sample.last ? root.sample.last : null
  readonly property var table: Nfl.divisionRows(root.club)
  readonly property int pollMs: {
    var n = Number(root.sample && root.sample.pollMs)
    if (!isFinite(n) || n < 15000) return 60000
    if (n > 300000) return 300000
    return Math.round(n)
  }

  // Room decides how much of each card is drawn. A tile here is about 270
  // pixels; these keep a smaller one readable rather than crowded.
  readonly property int pad: Style.space(12)
  readonly property real innerH: Math.max(0, root.height - root.pad * 2)
  readonly property bool tall: root.innerH >= Style.space(240)
  readonly property bool cramped: root.innerH < Style.space(210)
  readonly property int rowH: Math.round(Math.max(Style.space(30), Math.min(Style.space(46), root.innerH * 0.17)))
  readonly property int heroPx: Math.round(root.rowH * 0.88)
  readonly property int logoPx: root.rowH - Style.space(8)

  // Where a click lands: the game being shown, else the club's next one, else
  // the club page. The host checks the prefix before it launches anything.
  readonly property string tileUrl: {
    var candidate = ""
    if (root.mode === "board") candidate = ""
    else if (root.shown && root.shown.url) candidate = String(root.shown.url)
    else if (root.nextGame && root.nextGame.url) candidate = String(root.nextGame.url)
    else if (root.club && root.club.url) candidate = String(root.club.url)
    if (candidate.indexOf("https://www.nfl.com/") !== 0) return ""
    return candidate
  }

  function alpha(a) {
    return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, a)
  }

  function logoFor(side) {
    var path = Nfl.logoPath(side, root.darkPaper)
    return path ? Qt.resolvedUrl(path) : ""
  }

  // The club's own color where it stands off the tile, else the ink.
  function tintOf(side) {
    return Nfl.tint(side, root.paperHex, root.inkHex)
  }

  function openGame(game) {
    if (!game) return
    root.openUrl(String(game.url || ""))
  }

  function openUrl(url) {
    var value = String(url || "").trim()
    if (value.indexOf("https://www.nfl.com/") !== 0) return
    if (root.host && root.host.openUrl) root.host.openUrl(value)
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("nfl.py")
    args: root.teamId > 0 ? ["--team", String(root.teamId)] : []
    interval: root.pollMs
    active: root.visible
    onSampled: function(data) {
      if (data && data.ok) {
        root.sample = data
        root.haveScore = true
      } else if (!root.haveScore) {
        root.sample = data || {
          ok: false, mode: "empty", banner: "NFL", error: "Scores unavailable",
          focus: null, games: [], next: null, team: null
        }
      }
      root.loaded = true
    }
  }

  // A new club drops the old one's payload. Poller sees the new --team and
  // throws away a reply still in flight.
  onTeamIdChanged: {
    root.sample = ({})
    root.haveScore = false
    root.loaded = false
  }

  // ================================================================ pieces

  component ClubLogo: Image {
    property var side: null
    property int size: Style.space(24)
    width: size
    height: size
    source: root.logoFor(side)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: true
    sourceSize.width: 96
    sourceSize.height: 96
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.ink
    opacity: 0.55
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    elide: Text.ElideRight
  }

  // Three short bars under a club, one per timeout still in hand.
  component Timeouts: Row {
    id: timeouts
    property int remaining: -1
    visible: remaining >= 0
    spacing: Style.space(3)
    Repeater {
      model: 3
      Rectangle {
        required property int index
        width: Style.space(9)
        height: Style.space(3)
        radius: height / 2
        color: root.ink
        opacity: index < timeouts.remaining ? 0.85 : 0.15
      }
    }
  }

  // One side of a score bug: logo, ticker and record, then the score. On a
  // final the middle carries points by quarter; while live it carries the
  // timeouts and whoever has the ball.
  component ScoreRow: Item {
    id: scoreRow
    property var game: null
    property var side: null
    property bool showLines: false
    property var cells: []
    property real cellW: Style.space(20)
    readonly property bool dim: Nfl.trailing(scoreRow.game, scoreRow.side)
    readonly property bool mine: !!(scoreRow.game && scoreRow.side
      && ((scoreRow.game.favorite === "away" && scoreRow.side === scoreRow.game.away)
       || (scoreRow.game.favorite === "home" && scoreRow.side === scoreRow.game.home)))
    height: root.rowH

    // The club's own row gets a thin edge in its color.
    Rectangle {
      visible: scoreRow.mine
      x: -Style.space(7)
      width: Style.space(3)
      height: Math.round(parent.height * 0.62)
      anchors.verticalCenter: parent.verticalCenter
      radius: width / 2
      color: root.tintOf(scoreRow.side)
    }

    ClubLogo {
      id: rowLogo
      side: scoreRow.side
      size: root.logoPx
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      opacity: scoreRow.dim ? 0.8 : 1
    }

    Column {
      id: nameCol
      anchors.left: rowLogo.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Row {
        spacing: Style.space(6)

        Text {
          id: abbrText
          textFormat: Text.PlainText
          text: Nfl.teamAbbr(scoreRow.side)
          color: root.ink
          opacity: scoreRow.dim ? 0.55 : 1
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          font.letterSpacing: 0.5
        }

        Text {
          anchors.baseline: abbrText.baseline
          visible: !scoreRow.showLines && text !== ""
          textFormat: Text.PlainText
          text: String((scoreRow.side && scoreRow.side.record) || "")
          color: root.ink
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.features: ({ "tnum": 1 })
        }
      }

      Timeouts {
        visible: !scoreRow.showLines && remaining >= 0
        remaining: Nfl.timeoutsLeft(scoreRow.side)
      }
    }

    // Points by quarter, right-aligned against the total.
    Row {
      visible: scoreRow.showLines
      anchors.right: scoreText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      Repeater {
        model: scoreRow.cells
        Text {
          required property var modelData
          width: scoreRow.cellW
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: String(modelData)
          color: root.ink
          opacity: scoreRow.dim ? 0.4 : 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.features: ({ "tnum": 1 })
        }
      }
    }

    // Whoever has the ball, in their own color.
    Text {
      visible: Nfl.isOffense(scoreRow.game, scoreRow.side)
      anchors.right: scoreText.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Nfl.FOOTBALL
      color: root.tintOf(scoreRow.side)
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
    }

    Text {
      id: scoreText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Nfl.sideScore(scoreRow.side)
      color: root.ink
      opacity: scoreRow.dim ? 0.4 : 1
      font.family: root.fontFamily
      font.pixelSize: root.heroPx
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
    }
  }

  // The field, drawn from the offence's side: its own goal on the left, the
  // goal it attacks on the right, the ball on the line of scrimmage and the
  // yellow line where the next first down is.
  component Field: Item {
    id: field
    property var game: null
    property var offense: null
    property var defense: null
    readonly property var marks: Nfl.fieldMarks(field.game)
    readonly property real zone: Math.round(width / 11)
    readonly property real playW: width - zone * 2
    function xAt(yard) { return field.zone + (yard / 100) * field.playW }

    Rectangle {
      id: turf
      anchors.fill: parent
      radius: Style.space(4)
      color: root.alpha(0.06)
      border.width: 1
      border.color: root.alpha(0.14)
    }

    // The red zone, once the offence is inside the 20.
    Rectangle {
      visible: !!(field.game && field.game.redZone)
      x: field.xAt(80)
      width: field.xAt(100) - x
      height: parent.height - 2
      y: 1
      color: Color.urgent
      opacity: 0.16
    }

    Repeater {
      model: [10, 20, 30, 40, 50, 60, 70, 80, 90]
      Rectangle {
        required property int modelData
        x: Math.round(field.xAt(modelData))
        width: 1
        height: modelData === 50 ? parent.height - 4 : Math.round(parent.height * 0.4)
        anchors.verticalCenter: parent.verticalCenter
        color: root.ink
        opacity: modelData === 50 ? 0.28 : 0.13
      }
    }

    Repeater {
      model: [
        { side: field.offense, left: true },
        { side: field.defense, left: false }
      ]
      Rectangle {
        required property var modelData
        x: modelData.left ? 1 : parent.width - width - 1
        y: 1
        width: field.zone - 1
        height: parent.height - 2
        radius: Style.space(3)
        color: root.tintOf(modelData.side)
        opacity: 0.85

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: Nfl.teamAbbr(modelData.side)
          color: Nfl.inkOn(root.tintOf(modelData.side))
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 1)
          font.weight: Font.Bold
          rotation: modelData.left ? -90 : 90
        }
      }
    }

    // Line to gain.
    Rectangle {
      visible: !!field.marks && field.marks.line !== null && field.marks.line < 100
      x: Math.round(field.xAt(field.marks && field.marks.line !== null ? field.marks.line : 0)) - 1
      width: 2
      height: parent.height - 2
      y: 1
      color: "#f2c230"
    }

    // Line of scrimmage, then the ball on it.
    Rectangle {
      visible: !!field.marks
      x: Math.round(field.xAt(field.marks ? field.marks.ball : 0)) - 1
      width: 2
      height: parent.height - 2
      y: 1
      color: "#4f8ff7"
    }

    Rectangle {
      visible: !!field.marks
      width: Style.space(12)
      height: Style.space(7)
      radius: height / 2
      x: field.xAt(field.marks ? field.marks.ball : 0) - width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: "#8a4b26"
      border.width: 1
      border.color: "#f4e9dc"

      Rectangle {
        anchors.centerIn: parent
        width: Math.max(2, parent.width * 0.35)
        height: 1
        color: "#f4e9dc"
      }
    }
  }

  component SlateSide: Row {
    id: slateSide
    property var game: null
    property var side: null
    readonly property bool dim: Nfl.trailing(slateSide.game, slateSide.side)
    readonly property bool played: !!(slateSide.game && (slateSide.game.live || slateSide.game.finished))
    spacing: Style.space(4)
    width: slate.sideW

    ClubLogo {
      anchors.verticalCenter: parent.verticalCenter
      side: slateSide.side
      size: slate.logoPx
      opacity: slateSide.dim ? 0.55 : 1
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: abbrGauge.implicitWidth
      textFormat: Text.PlainText
      text: Nfl.teamAbbr(slateSide.side)
      color: root.ink
      opacity: slateSide.dim ? 0.5 : (slateSide.played ? 1 : 0.8)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: slateSide.played && !slateSide.dim ? Font.DemiBold : Font.Normal
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: scoreGauge.implicitWidth
      horizontalAlignment: Text.AlignRight
      visible: slateSide.played
      textFormat: Text.PlainText
      text: Nfl.sideScore(slateSide.side)
      color: root.ink
      opacity: slateSide.dim ? 0.5 : 1
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
    }
  }

  // ============================================================== the tile

  Rectangle {
    anchors.fill: parent
    visible: root.teamColors && !!root.club
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.2) }
      GradientStop { position: 0.55; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.05) }
      GradientStop { position: 1; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.02) }
    }
  }

  Item {
    id: page
    anchors.fill: parent
    anchors.margins: root.pad

    WidgetHeader {
      id: header
      visible: root.loaded && !root.failed && root.mode !== "empty"
      title: {
        if (root.mode === "live") return "LIVE" + (Nfl.weekLine(root.shown) ? " · " + Nfl.weekLine(root.shown) : "")
        if (root.mode === "final") return Nfl.kickoffLine(root.shown) + (Nfl.weekLine(root.shown) ? " · " + Nfl.weekLine(root.shown) : "")
        if (root.mode === "upcoming") {
          var week = Nfl.weekLine(root.shown) || "NEXT GAME"
          return root.club && root.club.onBye ? "BYE · " + week : week
        }
        if (root.mode === "closed") return "SEASON COMPLETE"
        if (root.mode === "board") return Nfl.weekLine(root.games.length ? root.games[0] : null) || "NFL"
        return "NFL"
      }
      trailing: {
        if (root.mode === "board") {
          var live = Number(root.sample && root.sample.liveCount) || 0
          var count = Number(root.sample && root.sample.gameCount) || root.games.length
          return (live ? live + " LIVE · " : "") + count + " GAMES"
        }
        if (root.mode === "closed") return root.club ? String(root.club.divisionName || "") : ""
        return root.shown ? String(root.shown.network || "") : ""
      }
      readonly property bool anyLive: root.mode === "live"
        || (root.mode === "board" && Number(root.sample && root.sample.liveCount) > 0)
      dotColor: anyLive ? Color.urgent : root.ink
      dotOpacity: anyLive ? 1 : 0.35
      pulse: anyLive
      fontFamily: root.fontFamily
      foreground: root.ink
    }

    // ======================================================== live and final
    Item {
      id: gameCard
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: root.mode === "live" || root.mode === "final"

      readonly property var away: root.shown ? root.shown.away : null
      readonly property var home: root.shown ? root.shown.home : null
      readonly property var offense: Nfl.isOffense(root.shown, gameCard.away) ? gameCard.away
        : (Nfl.isOffense(root.shown, gameCard.home) ? gameCard.home : null)
      readonly property var defense: gameCard.offense === gameCard.away ? gameCard.home
        : (gameCard.offense === gameCard.home ? gameCard.away : null)
      readonly property var line: Nfl.lineTable(root.shown)
      readonly property bool final: root.mode === "final"
      readonly property bool driving: root.mode === "live" && !!Nfl.fieldMarks(root.shown)
      // Between plays, at the half, and after the whistle the drive has
      // nothing to say, so the card turns into a box score.
      readonly property bool boxScore: gameCard.final || (root.mode === "live" && !gameCard.driving)
      // Quarter columns share what is left after the logo, the ticker and
      // the total.
      readonly property real cellW: {
        var room = width - root.logoPx - Style.space(8) - Style.space(44) - Style.space(8) - totalGauge.implicitWidth
        return Math.max(Style.space(14), Math.min(Style.space(24), Math.floor(room / Math.max(4, gameCard.line.labels.length))))
      }
      readonly property bool showLines: gameCard.boxScore && gameCard.line.played > 0

      // The quarter labels over the line score.
      Row {
        id: quarterHead
        visible: gameCard.showLines
        height: visible ? Style.font.caption + Style.space(2) : 0
        anchors.right: parent.right
        anchors.rightMargin: totalGauge.implicitWidth + Style.space(8)
        Repeater {
          model: gameCard.line.labels
          Text {
            required property var modelData
            width: gameCard.cellW
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: String(modelData)
            color: root.ink
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        id: totalGauge
        visible: false
        text: "00"
        font.family: root.fontFamily
        font.pixelSize: root.heroPx
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
      }

      Column {
        id: rows
        anchors.top: quarterHead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        ScoreRow {
          width: rows.width
          game: root.shown
          side: gameCard.away
          showLines: gameCard.showLines
          cells: gameCard.line.away
          cellW: gameCard.cellW
        }

        ScoreRow {
          width: rows.width
          game: root.shown
          side: gameCard.home
          showLines: gameCard.showLines
          cells: gameCard.line.home
          cellW: gameCard.cellW
        }
      }

      // ------------------------------------------------------------ live
      Column {
        id: liveBlock
        visible: root.mode === "live"
        anchors.top: rows.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(8)

        // The clock in a box, then the down and the spot.
        Item {
          width: parent.width
          height: clockBox.height

          Rectangle {
            id: clockBox
            width: clockText.implicitWidth + Style.space(12)
            height: clockText.implicitHeight + Style.space(4)
            radius: Style.space(4)
            color: root.alpha(0.1)

            Text {
              id: clockText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.shown ? String(root.shown.time || "LIVE").toUpperCase() : ""
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.Bold
              font.features: ({ "tnum": 1 })
            }
          }

          Text {
            anchors.left: clockBox.right
            anchors.leftMargin: Style.space(8)
            anchors.right: winText.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: clockBox.verticalCenter
            textFormat: Text.PlainText
            text: Nfl.driveLine(root.shown)
            color: root.shown && root.shown.redZone ? Color.urgent : root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
          }

          Text {
            id: winText
            anchors.right: parent.right
            anchors.verticalCenter: clockBox.verticalCenter
            textFormat: Text.PlainText
            // The down and distance come first; the odds only when there is room.
            text: parent.width >= Style.space(250) ? Nfl.winLine(root.shown) : ""
            color: root.ink
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: ({ "tnum": 1 })
          }
        }

        Field {
          width: parent.width
          height: visible ? Style.space(30) : 0
          visible: gameCard.driving && !root.cramped
          game: root.shown
          offense: gameCard.offense
          defense: gameCard.defense
        }

        Caption {
          width: parent.width
          visible: gameCard.driving && text !== ""
          text: root.shown ? String(root.shown.drive || "") : ""
          opacity: 0.6
        }
      }

      Text {
        anchors.top: liveBlock.bottom
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: gameCard.driving && Nfl.lastPlay(root.shown) !== ""
        clip: true
        wrapMode: Text.WordWrap
        maximumLineCount: root.tall ? 3 : 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: Nfl.lastPlay(root.shown)
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // ------------------------------------------------------ box score
      Column {
        id: boxBlock
        visible: gameCard.boxScore && !root.cramped
        anchors.top: gameCard.final ? rows.bottom : liveBlock.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(3)

        Rectangle {
          width: parent.width
          height: 1
          color: root.ink
          opacity: 0.1
          visible: gameCard.final
        }

        Item { width: 1; height: Style.space(2); visible: gameCard.final }

        Repeater {
          model: Nfl.leaderRows(root.shown)

          Item {
            required property var modelData
            width: parent.width
            height: Style.font.caption + Style.space(6)

            Text {
              id: catText
              width: Style.space(34)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.cat
              color: root.ink
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: 0.6
            }

            ClubLogo {
              id: leaderLogo
              anchors.left: catText.right
              anchors.verticalCenter: parent.verticalCenter
              side: ({ abbr: modelData.team })
              size: Style.space(13)
            }

            Text {
              id: leaderName
              anchors.left: leaderLogo.right
              anchors.leftMargin: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.4)
              textFormat: Text.PlainText
              text: modelData.name
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Caption {
              anchors.left: leaderName.right
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.line
              opacity: 0.6
            }
          }
        }
      }

      // The wire recap, between the box score and the next game.
      Text {
        anchors.top: boxBlock.visible ? boxBlock.bottom : rows.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: nextRow.visible ? nextRow.top : parent.bottom
        anchors.bottomMargin: Style.space(4)
        visible: gameCard.final && text !== ""
        clip: true
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.shown ? String(root.shown.headline || "") : ""
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // A final looks back, so it ends looking forward.
      Item {
        id: nextRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.font.caption + Style.space(4)
        visible: gameCard.final && !!root.nextGame

        Text {
          id: nextLabel
          width: Style.space(34)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "NEXT"
          color: root.ink
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: 0.6
        }

        Caption {
          anchors.left: nextLabel.right
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          opacity: 0.8
          text: {
            if (!root.nextGame) return ""
            var bits = [Nfl.opponentLine(root.nextGame), Nfl.kickoffLine(root.nextGame)]
            if (root.nextGame.network) bits.push(String(root.nextGame.network))
            return bits.join(" · ")
          }
        }
      }
    }

    // ============================================== the next game, or none
    Item {
      id: nextCard
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: root.mode === "upcoming" || root.mode === "closed"

      readonly property bool upcoming: root.mode === "upcoming"
      readonly property int bigLogo: Math.round(Math.max(Style.space(30), Math.min(Style.space(46), root.innerH * 0.17)))
      // The division table takes whatever the hero and the footer leave.
      readonly property real tableRoom: nextCard.height - hero.height - Style.space(10)
        - (Style.font.caption + Style.space(4)) - (Style.font.caption + Style.space(2)) - Style.space(6)
      readonly property int tableRowH: Math.max(Style.font.caption + Style.space(5),
        Math.min(Style.font.caption + Style.space(12), Math.floor(nextCard.tableRoom / Math.max(1, root.table.length))))

      Column {
        id: hero
        width: parent.width
        spacing: Style.space(4)

        // Away @ home, each under its logo.
        Item {
          visible: nextCard.upcoming
          width: parent.width
          height: visible ? nextCard.bigLogo + Style.font.body + Style.space(6) : 0

          Repeater {
            model: [
              { side: root.shown ? root.shown.away : null, left: true },
              { side: root.shown ? root.shown.home : null, left: false }
            ]

            Column {
              required property var modelData
              readonly property bool mine: !!(root.shown && modelData.side
                && ((root.shown.favorite === "away" && modelData.left)
                 || (root.shown.favorite === "home" && !modelData.left)))
              width: parent.width * 0.36
              x: modelData.left ? parent.width * 0.06 : parent.width * 0.58
              spacing: Style.space(4)

              ClubLogo {
                anchors.horizontalCenter: parent.horizontalCenter
                side: modelData.side
                size: nextCard.bigLogo
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(5)

                Text {
                  id: heroAbbr
                  textFormat: Text.PlainText
                  text: Nfl.teamAbbr(modelData.side)
                  color: root.ink
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.weight: parent.parent.mine ? Font.Bold : Font.DemiBold
                }

                Text {
                  anchors.baseline: heroAbbr.baseline
                  textFormat: Text.PlainText
                  text: String((modelData.side && modelData.side.record) || "")
                  color: root.ink
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.features: ({ "tnum": 1 })
                }
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(nextCard.bigLogo / 2 - height / 2)
            textFormat: Text.PlainText
            text: root.shown && root.shown.neutral ? "vs" : "@"
            color: root.ink
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
        }

        Text {
          visible: nextCard.upcoming
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: Nfl.whenLine(root.shown)
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          font.features: ({ "tnum": 1 })
          elide: Text.ElideRight
        }

        Caption {
          visible: nextCard.upcoming && text !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: {
            var bits = []
            var place = Nfl.venueLine(root.shown)
            if (place) bits.push(place)
            if (root.tall) {
              var odds = Nfl.oddsLine(root.shown)
              if (odds) bits.push(odds)
            }
            return bits.join(" · ")
          }
        }

        Caption {
          visible: nextCard.upcoming && root.tall && text !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.shown ? String(root.shown.weather || "") : ""
          opacity: 0.45
        }

        // Season over: the club and how it went.
        Row {
          visible: !nextCard.upcoming
          width: parent.width
          height: visible ? nextCard.bigLogo : 0
          spacing: Style.space(10)

          ClubLogo {
            side: root.club
            size: nextCard.bigLogo
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - nextCard.bigLogo - parent.spacing
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Nfl.teamLine(root.club)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Caption {
              width: parent.width
              opacity: 0.7
              text: {
                if (!root.club) return ""
                var bits = []
                if (root.club.record) bits.push(String(root.club.record))
                var seed = Nfl.seedLine(root.club)
                if (seed) bits.push(seed + " SEED")
                return bits.join(" · ")
              }
            }
          }
        }
      }

      // The division, in NFL.com's order, the club's row lit.
      Column {
        id: divisionTable
        visible: root.table.length > 0 && nextCard.tableRoom >= root.table.length * (Style.font.caption + Style.space(5))
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(10)
        width: parent.width
        spacing: 0
        readonly property int colW: Style.space(36)

        Item {
          width: parent.width
          height: Style.font.caption + Style.space(4)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.club ? String(root.club.divisionName || "").toUpperCase() : ""
            color: root.ink
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: 0.8
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
              model: ["W-L", "DIFF", "STRK"]
              Text {
                required property var modelData
                width: divisionTable.colW
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: modelData
                color: root.ink
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
              }
            }
          }
        }

        Repeater {
          model: root.table

          Item {
            required property var modelData
            width: divisionTable.width
            height: nextCard.tableRowH

            Rectangle {
              visible: !!modelData.favorite
              anchors.fill: parent
              anchors.leftMargin: -Style.space(4)
              anchors.rightMargin: -Style.space(4)
              radius: Style.space(4)
              color: root.alpha(0.09)
            }

            ClubLogo {
              id: tableLogo
              side: modelData
              size: Style.space(15)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              anchors.left: tableLogo.right
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(modelData.abbr || "")
              color: root.ink
              opacity: modelData.favorite ? 1 : 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: modelData.favorite ? Font.Bold : Font.Normal
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              Repeater {
                model: [String(modelData.record || ""), Nfl.differential(modelData.differential), String(modelData.streak || "")]
                Text {
                  required property var modelData
                  width: divisionTable.colW
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: modelData
                  color: root.ink
                  opacity: parent.parent.modelData.favorite ? 1 : 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: parent.parent.modelData.favorite ? Font.DemiBold : Font.Normal
                  font.features: ({ "tnum": 1 })
                }
              }
            }
          }
        }
      }

      // The club in four numbers, when there is no division table to carry them.
      Row {
        id: statRow
        visible: !divisionTable.visible && !!root.club
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(12)
        width: parent.width

        Repeater {
          model: [
            { label: "REC", value: root.club ? String(root.club.record || "—") : "—" },
            { label: "STRK", value: root.club ? (String(root.club.streak || "") || "—") : "—" },
            { label: "DIFF", value: root.club ? Nfl.differential(root.club.differential) : "—" },
            { label: "SEED", value: root.club ? (Nfl.seedLine(root.club) || "—") : "—" }
          ]

          Column {
            required property var modelData
            width: statRow.width / 4
            spacing: Style.space(1)

            Caption {
              width: parent.width
              text: String(modelData.label)
              opacity: 0.42
              font.letterSpacing: 0.6
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(modelData.value)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }
          }
        }
      }

      // Last result on the left, the seed on the right.
      Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.font.caption + Style.space(2)
        visible: divisionTable.visible && (!!root.lastGame || Nfl.seedLine(root.club) !== "")

        Text {
          id: lastLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          visible: !!root.lastGame
          textFormat: Text.PlainText
          text: "LAST"
          color: root.ink
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: 0.6
        }

        Caption {
          anchors.left: lastLabel.right
          anchors.leftMargin: Style.space(6)
          anchors.right: seedText.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: !!root.lastGame
          text: Nfl.resultLine(root.lastGame)
          opacity: 0.8
        }

        Caption {
          id: seedText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: text !== ""
          text: Nfl.seedLine(root.club) ? "SEED " + Nfl.seedLine(root.club) : ""
          opacity: 0.6
          font.letterSpacing: 0.6
        }
      }
    }

    // ============================================================ the slate
    Column {
      id: slate
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      anchors.left: parent.left
      anchors.right: parent.right
      visible: root.mode === "board"

      readonly property int count: Math.max(1, Math.min(root.games.length, Math.floor((page.height - header.height - Style.space(6)) / Style.space(22))))
      readonly property real rowH: Math.min(Style.space(30), Math.floor((page.height - header.height - Style.space(6)) / slate.count))
      readonly property int logoPx: Math.round(Math.min(Style.space(18), slate.rowH * 0.62))
      readonly property real sideW: slate.logoPx + Style.space(4) + abbrGauge.implicitWidth + Style.space(4) + scoreGauge.implicitWidth

      FontMetrics {
        id: stateMetrics
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text { id: abbrGauge; visible: false; text: "WWW"; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.weight: Font.DemiBold }
      Text { id: scoreGauge; visible: false; text: "00"; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }) }

      Repeater {
        model: slate.count

        Item {
          id: slateRow
          required property int index
          readonly property var game: root.games[slateRow.index]
          readonly property bool live: !!(slateRow.game && slateRow.game.live)
          width: slate.width
          height: slate.rowH

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -Style.space(4)
            anchors.rightMargin: -Style.space(4)
            radius: Style.space(4)
            color: root.alpha(0.07)
            visible: rowMouse.containsMouse
          }

          Rectangle {
            id: liveDot
            width: Style.space(5)
            height: width
            radius: width / 2
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Color.urgent
            visible: slateRow.live
          }

          SlateSide {
            id: awaySide
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            game: slateRow.game
            side: slateRow.game ? slateRow.game.away : null
          }

          Text {
            id: atText
            anchors.left: awaySide.right
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "@"
            color: root.ink
            opacity: 0.3
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          SlateSide {
            id: homeSide
            anchors.left: atText.right
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            game: slateRow.game
            side: slateRow.game ? slateRow.game.home : null
          }

          Text {
            anchors.left: homeSide.right
            anchors.leftMargin: Style.space(6)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: {
              var full = Nfl.boardState(slateRow.game, false)
              return stateMetrics.advanceWidth(full) <= width ? full : Nfl.boardState(slateRow.game, true)
            }
            color: slateRow.live ? Color.urgent : root.ink
            opacity: slateRow.live ? 1 : (slateRow.game && slateRow.game.finished ? 0.5 : 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: slateRow.live ? Font.DemiBold : Font.Normal
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
          }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            visible: slateRow.index < slate.count - 1
            color: root.ink
            opacity: 0.07
          }

          // A slate row is its own target so a click lands on that game.
          MouseArea {
            id: rowMouse
            z: 3
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openGame(slateRow.game)
          }
        }
      }
    }

    // Nothing to show yet, or the feed failed. Named so the tile still says
    // something useful.
    Column {
      id: placeholder
      anchors.centerIn: parent
      width: parent.width - Style.space(16)
      spacing: Style.space(6)
      visible: !root.loaded || root.failed || root.mode === "empty" || root.mode === ""

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Nfl.FOOTBALL
        color: root.ink
        opacity: root.failed ? 0.4 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading * 2
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Nfl.emptyHeadline(root.mode, root.failed ? "error" : "", root.loaded)
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: Nfl.emptyBody(root.mode, root.failed ? "error" : "", root.loaded)
        color: root.ink
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // A click on a club card opens the game being shown; a click on a slate
  // row opens that row's game.
  MouseArea {
    z: 2
    anchors.fill: parent
    enabled: root.mode !== "board" && root.tileUrl.length > 0
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.openUrl(root.tileUrl)
  }
}
