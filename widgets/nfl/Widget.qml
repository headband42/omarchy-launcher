import QtQuick
import Quickshell.Io
import qs.Commons
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
  readonly property color wash: root.teamColors && root.club ? String(root.club.color || "") : ""
  // Team color tints the background only. Ink stays the menu's own text color
  // so a near-black club color can never leave the tile unreadable.
  readonly property color ink: root.foreground
  readonly property string mode: String((root.sample && root.sample.mode) || "")
  readonly property bool failed: root.loaded && !!root.sample && root.sample.ok === false
  readonly property var shown: root.sample && root.sample.focus ? root.sample.focus : null
  readonly property var games: {
    var rows = root.sample && root.sample.games
    return rows && rows.length ? rows : []
  }
  readonly property var nextGame: root.sample && root.sample.next ? root.sample.next : null
  readonly property var lastGame: root.sample && root.sample.last ? root.sample.last : null
  readonly property int pollMs: {
    var n = Number(root.sample && root.sample.pollMs)
    if (!isFinite(n) || n < 15000) return 60000
    if (n > 300000) return 300000
    return Math.round(n)
  }
  readonly property bool compact: Nfl.compact(root.height)
  readonly property bool roomy: Nfl.roomy(root.height)
  readonly property int heroPx: Nfl.heroSize(root.width, root.height)
  // The opponent's name is the whole point of the between-games tile, so it
  // is the largest thing there, but the score size is for numbers and swamped
  // a name that is already long.
  readonly property int cardPx: Math.max(Style.font.title, Math.round(Math.min(root.width * 0.085, 26)))
  readonly property string eyebrow: {
    if (root.mode === "board") return "NFL"
    return Nfl.teamLine(root.club) || "NFL"
  }
  readonly property string status: String((root.sample && root.sample.summary) || "")
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
  readonly property int boardCount: Math.min(root.games.length, root.roomy ? 8 : 6)

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function logoFor(side) {
    var abbr = Nfl.teamAbbr(side)
    if (!abbr) return ""
    return "logos/" + abbr.toUpperCase() + ".png"
  }

  function sideColor(side) {
    var hex = String((side && side.color) || "")
    if (hex.length !== 7 || hex.charAt(0) !== "#") return root.foreground
    return hex
  }

  function refresh() {
    if (!root.visible) return
    if (probe.running) {
      probe.again = true
      return
    }
    var args = ["/usr/bin/python3", root.scriptPath("sample.py")]
    if (root.teamId > 0) args.push("--team", String(root.teamId))
    probe.team = root.teamId
    probe.command = args
    probe.running = true
  }

  Process {
    id: probe
    property bool again: false
    property int team: -1
    command: ["/usr/bin/python3", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      // A club change while this process was running. Drop the old payload.
      if (probe.team !== root.teamId) {
        probe.again = false
        if (root.visible) Qt.callLater(root.refresh)
        return
      }
      var parsed = null
      try { parsed = JSON.parse(probeOut.text || "") } catch (e) { parsed = null }
      if (parsed && parsed.ok) {
        root.sample = parsed
        root.haveScore = true
      } else if (!root.haveScore) {
        root.sample = parsed || {
          ok: false, mode: "empty", banner: "NFL", error: "Scores unavailable",
          summary: "", focus: null, games: [], next: null, team: null
        }
      }
      root.loaded = true
      if (probe.again) {
        probe.again = false
        Qt.callLater(root.refresh)
        return
      }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: root.pollMs
    onTriggered: root.refresh()
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    visible: root.wash !== ""
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.32) }
      GradientStop { position: 1; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.06) }
    }
  }

  // Everything above the club row. The cards live in here so none of them
  // can run under the stats.
  Item {
    id: contentArea
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: statRow.visible ? statRow.top : parent.bottom
    anchors.margins: Style.space(14)

    // =========================================================== live game
    //
    // Logo, score, and the game itself, in the order a broadcast puts them:
    // who, how much, where the ball is, and what just happened. The field is
    // a strip rather than a pitch, because a tile is 300 pixels wide and the
    // information in a drive is the line of scrimmage, not the shape of it.
    Item {
      id: gameCard
      anchors.fill: parent
      visible: root.mode === "live" || root.mode === "final"
    readonly property var away: root.shown ? root.shown.away : null
    readonly property var home: root.shown ? root.shown.home : null

    // The score row sizes itself from its columns' content. A Row whose
    // children are bound back to the Row's height resolves to zero, which is
    // how a live tile ends up with no score on it at all.
    Row {
      id: scoreRow
      width: parent.width
      height: Math.max(awayColumn.implicitHeight, homeColumn.implicitHeight)
      spacing: Style.space(6)

      Item {
        width: (scoreRow.width - scoreRow.spacing * 2) * 0.38
        height: scoreRow.height

        Row {
          id: awayMark
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Image {
            id: awayLogo
            width: Math.round(root.heroPx * 0.92)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: root.logoFor(gameCard.away)
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: true
            asynchronous: true
          }

          Column {
            id: awayColumn
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              textFormat: Text.PlainText
              text: Nfl.teamAbbr(gameCard.away)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: 0.5
            }

            Text {
              textFormat: Text.PlainText
              text: Nfl.sideScore(gameCard.away)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: root.heroPx
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }

            Text {
              visible: !root.compact
              textFormat: Text.PlainText
              text: String((gameCard.away && gameCard.away.record) || "")
              color: root.ink
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.features: ({ "tnum": 1 })
            }
          }
        }
      }

      // The middle carries the game: the quarter and clock over the drive.
      Column {
        width: (scoreRow.width - scoreRow.spacing * 2) * 0.24
        height: scoreRow.height
        spacing: 1

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: {
            if (!root.shown) return ""
            if (root.shown.finished) return "FINAL"
            return String(root.shown.time || "")
          }
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Math.max(Style.font.body, Math.round(root.heroPx * 0.5))
          font.weight: Font.DemiBold
          font.features: ({ "tnum": 1 })
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: Nfl.situationLine(root.shown) !== ""
          textFormat: Text.PlainText
          text: root.shown ? String(root.shown.downDistance || "") : ""
          color: root.ink
          opacity: 0.85
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: !!(root.shown && root.shown.ball)
          textFormat: Text.PlainText
          text: root.shown ? String(root.shown.ball || "") : ""
          color: root.ink
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.DemiBold
        }
      }

      Item {
        width: (scoreRow.width - scoreRow.spacing * 2) * 0.38
        height: scoreRow.height

        Row {
          id: homeMark
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          // Width comes from the content. A Text whose width is bound to
          // its Column's implicitWidth makes that implicit width depend on
          // itself, and the column collapses to nothing: the same trap as the
          // row above, and just as invisible on the tile.
          Column {
            id: homeColumn
            width: Math.max(homeAbbr.implicitWidth, homeScore.implicitWidth, homeRecord.implicitWidth)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              id: homeAbbr
              width: parent.width
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Nfl.teamAbbr(gameCard.home)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: 0.5
            }

            Text {
              id: homeScore
              width: parent.width
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Nfl.sideScore(gameCard.home)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: root.heroPx
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }

            Text {
              id: homeRecord
              width: parent.width
              horizontalAlignment: Text.AlignRight
              visible: !root.compact
              textFormat: Text.PlainText
              text: String((gameCard.home && gameCard.home.record) || "")
              color: root.ink
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.features: ({ "tnum": 1 })
            }
          }

          Image {
            id: homeLogo
            width: Math.round(root.heroPx * 0.92)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: root.logoFor(gameCard.home)
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: true
            asynchronous: true
          }
        }
      }
    }

    // The field. ESPN gives the line of scrimmage from the offence's own goal
    // line, so the two sides sit on one number from opposite ends and the
    // ball reads as sitting between them.
    Item {
      id: field
      width: parent.width
      height: root.compact ? Style.space(26) : Style.space(34)
      visible: root.roomy && Nfl.hasField(root.shown)
      anchors.top: scoreRow.bottom
      anchors.topMargin: Style.space(8)

      readonly property real awayX: {
        var yard = Nfl.fieldYard(root.shown, gameCard.away)
        if (yard === null) return 0
        return (yard / 100) * (width - Style.space(10))
      }
      readonly property real homeX: {
        var yard = Nfl.fieldYard(root.shown, gameCard.home)
        if (yard === null) return 0
        return (yard / 100) * (width - Style.space(10))
      }
      Rectangle {
        id: turf
        anchors.fill: parent
        radius: Style.space(6)
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)

        // Yard ticks, every 25. Enough to read a position off, few enough not
        // to turn a 300 pixel tile into graph paper.
        Repeater {
          model: [25, 50, 75]

          Rectangle {
            required property int modelData
            x: (modelData / 100) * (turf.width - Style.space(10)) + Style.space(5)
            width: 1
            height: parent.height * 0.5
            anchors.verticalCenter: parent.verticalCenter
            color: root.ink
            opacity: 0.14
          }
        }

        // The line of scrimmage sits under the ball.
        Rectangle {
          x: (field.awayX + field.homeX) / 2
          width: 2
          height: parent.height
          color: root.ink
          opacity: 0.5
        }

        Row {
          id: awayMarker
          x: field.awayX
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Rectangle {
            width: 9
            height: 9
            radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: root.sideColor(gameCard.away)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Nfl.teamAbbr(gameCard.away)
            color: root.ink
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 2)
            font.weight: Font.DemiBold
          }
        }

        Row {
          id: homeMarker
          x: field.homeX - width
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Nfl.teamAbbr(gameCard.home)
            color: root.ink
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 2)
            font.weight: Font.DemiBold
          }

          Rectangle {
            width: 9
            height: 9
            radius: 4.5
            anchors.verticalCenter: parent.verticalCenter
            color: root.sideColor(gameCard.home)
          }
        }
      }
    }

    // What just happened, and who called it.
    Item {
      id: play
      width: parent.width
      height: playLine.implicitHeight + (root.roomy && Nfl.lastPlay(root.shown) ? playText.implicitHeight : 0)
      visible: !!(root.shown && (root.shown.network || Nfl.lastPlay(root.shown)))
      anchors.top: (root.roomy && Nfl.hasField(root.shown)) ? field.bottom : scoreRow.bottom
      anchors.topMargin: Style.space(8)

      Row {
        id: playLine
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: root.shown ? String(root.shown.network || "") : ""
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.DemiBold
          font.letterSpacing: 0.5
        }

        Text {
          textFormat: Text.PlainText
          text: root.shown && root.shown.network && Nfl.lastPlay(root.shown) ? "·" : ""
          color: root.ink
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
        }

        Text {
          width: Math.max(0, parent.width - x)
          textFormat: Text.PlainText
          text: root.shown ? String(root.shown.downDistance || "") : ""
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          font.weight: Font.Medium
          elide: Text.ElideRight
        }
      }

      Text {
        id: playText
        width: parent.width
        visible: root.roomy && Nfl.lastPlay(root.shown) !== ""
        anchors.top: playLine.bottom
        anchors.topMargin: Style.space(2)
        textFormat: Text.PlainText
        text: Nfl.lastPlay(root.shown)
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 2)
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
  }

    // ==================================================== between two games
    Item {
      id: nextCard
      anchors.fill: parent
      visible: root.mode === "upcoming" || root.mode === "closed"

    Column {
      id: nextBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.mode === "closed"
          ? (root.club ? root.club.city + " " + root.club.nickname : "NFL")
          : Nfl.opponentLine(root.nextGame, Nfl.teamAbbr(root.club))
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: root.cardPx
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.mode === "upcoming"
        textFormat: Text.PlainText
        text: {
          if (!root.nextGame) return ""
          var when = Nfl.kickoffLine(root.nextGame)
          var network = String(root.nextGame.network || "")
          return network ? when + " · " + network : when
        }
        color: root.ink
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.roomy && root.mode === "upcoming" && root.nextGame && root.nextGame.neutral
        textFormat: Text.PlainText
        text: "Neutral site"
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: root.roomy && root.lastGame
        textFormat: Text.PlainText
        text: root.lastGame ? "Last: " + Nfl.boardLine(root.lastGame) : ""
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.features: ({ "tnum": 1 })
        elide: Text.ElideRight
      }
    }
  }

    // ============================================================= the slate
    Item {
      id: slate
      anchors.fill: parent
      visible: root.mode === "board"

    Column {
      id: slateHead
      width: parent.width
      height: Style.font.caption + Style.space(6)
      spacing: 0

      Text {
        anchors.left: parent.left
        anchors.right: countText.left
        anchors.rightMargin: Style.space(8)
        textFormat: Text.PlainText
        text: "NFL"
        color: root.ink
        opacity: 0.62
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
      }

      Text {
        id: countText
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.games.length + " GAMES"
        color: root.ink
        opacity: 0.62
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
      }
    }

    Column {
      id: boardList
      width: parent.width
      height: parent.height - slateHead.height
      anchors.top: slateHead.bottom
      anchors.topMargin: Style.space(4)

      Repeater {
        model: root.boardCount

        Item {
          id: row
          required property int index
          width: boardList.width
          height: boardList.height / Math.max(1, root.boardCount)

          Image {
            id: rowLogo
            width: Math.max(10, Math.round(root.height * 0.045))
            height: width
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            source: root.logoFor(root.games[index] && root.games[index].away)
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: true
          }

          Text {
            id: rowText
            anchors.left: rowLogo.right
            anchors.leftMargin: Style.space(6)
            anchors.right: rowState.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Nfl.boardLine(root.games[index])
            color: root.ink
            opacity: root.games[index] && root.games[index].live ? 1 : 0.7
            font.family: root.fontFamily
            font.pixelSize: root.roomy ? Style.font.body : Style.font.caption
            font.weight: (root.games[index] && root.games[index].live) ? Font.DemiBold : Font.Normal
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
          }

          Text {
            id: rowState
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Nfl.boardState(root.games[index])
            color: root.ink
            opacity: root.games[index] && root.games[index].live ? 0.9 : 0.45
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Style.font.caption - 1)
            font.features: ({ "tnum": 1 })
            elide: Text.ElideRight
          }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            visible: row.index < root.boardCount - 1
            color: root.ink
            opacity: 0.08
          }

          // A board row is its own target so a click lands on that game.
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openGame(root.games[index])
          }
        }
      }
    }
  }
  }

  // =========================================================== the club row
  Row {
    id: statRow
    width: parent.width
    height: Style.space(34)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(14)
    anchors.rightMargin: Style.space(14)
    visible: root.mode !== "board" && !!root.club

    Repeater {
      model: [
        { label: "REC", value: root.club ? String(root.club.record || "—") : "—" },
        { label: "FORM", value: root.club ? (String(root.club.streak || "") || "—") : "—" },
        { label: "DIFF", value: root.club ? Nfl.differential(root.club.differential) : "—" },
        { label: "SEED", value: root.club ? (Nfl.standingLine(root.club) || "—") : "—" }
      ]

      Column {
        required property var modelData
        width: statRow.width / 4
        height: statRow.height
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(modelData.label)
          color: root.ink
          opacity: 0.42
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 3)
          font.weight: Font.Medium
          font.letterSpacing: 0.6
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(modelData.value)
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.features: ({ "tnum": 1 })
          elide: Text.ElideRight
        }
      }
    }
  }

  // Nothing to show yet, or the feed failed. Named so the tile still says
  // something useful.
  Column {
    id: placeholder
    anchors.centerIn: parent
    width: parent.width - Style.space(36)
    spacing: Style.space(7)
    visible: !root.loaded || root.failed || root.mode === "empty"

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
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A click on the club card opens the game being shown; a click on a slate
  // row opens that row's game.
  MouseArea {
    id: cardLink
    z: 2
    anchors.fill: parent
    enabled: root.mode !== "board" && root.tileUrl.length > 0
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.openUrl(root.tileUrl)
  }

  function openGame(game) {
    if (!game) return
    openUrl(String(game.url || ""))
  }

  function openUrl(url) {
    var value = String(url || "").trim()
    if (value.indexOf("https://www.nfl.com/") !== 0) return
    if (root.host && root.host.openUrl) root.host.openUrl(value)
  }

  Component.onCompleted: root.refresh()
  onVisibleChanged: if (visible) root.refresh()
  onTeamIdChanged: {
    root.sample = ({})
    root.haveScore = false
    root.loaded = false
    if (root.visible) root.refresh()
  }
}
