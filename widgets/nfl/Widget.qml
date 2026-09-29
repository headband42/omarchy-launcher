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

  // One side of a scoreboard: logo, ticker and record, and the score. The
  // score is the only big thing; everything else orients it.
  component TeamRow: Item {
    id: teamRow
    property var side: null
    property bool bright: true
    property bool ball: false
    property bool favorite: false
    property bool showRecord: true
    property int scorePx: 40

    // The favorite's edge bar, so the club's own row finds the eye first.
    Rectangle {
      width: 2
      height: Math.round(parent.height * 0.66)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: teamRow.favorite
      radius: 1
      color: root.sideColor(teamRow.side)
      opacity: 0.9
    }

    Image {
      id: mark
      width: Math.min(38, teamRow.height - 12)
      height: width
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      source: root.logoFor(teamRow.side)
      fillMode: Image.PreserveAspectFit
      smooth: true
      cache: true
      asynchronous: true
    }

    Column {
      anchors.left: mark.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        textFormat: Text.PlainText
        text: Nfl.teamAbbr(teamRow.side)
        color: root.ink
        opacity: teamRow.bright ? 1 : 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        font.letterSpacing: 0.5
      }

      Text {
        visible: teamRow.showRecord && String((teamRow.side && teamRow.side.record) || "") !== ""
        textFormat: Text.PlainText
        text: String((teamRow.side && teamRow.side.record) || "")
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 2)
        font.features: ({ "tnum": 1 })
      }
    }

    Text {
      id: score
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Nfl.sideScore(teamRow.side)
      color: root.ink
      opacity: teamRow.bright ? 1 : 0.45
      font.family: root.fontFamily
      font.pixelSize: teamRow.scorePx
      font.weight: Font.DemiBold
      font.features: ({ "tnum": 1 })
    }

    // Whoever has the ball, in their own color with a ring so it reads on
    // any wash.
    Rectangle {
      width: 8
      height: 8
      radius: 4
      anchors.right: score.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      visible: teamRow.ball
      color: root.sideColor(teamRow.side)
      border.width: 1
      border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
    }
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
      GradientStop { position: 0; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.22) }
      GradientStop { position: 1; color: Qt.rgba(root.wash.r, root.wash.g, root.wash.b, 0.05) }
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
    // A broadcast bug, top to bottom: where the game stands, who is ahead,
    // where the ball is, and what just happened.
    Item {
      id: gameCard
      anchors.fill: parent
      visible: root.mode === "live" || root.mode === "final"
      readonly property var away: root.shown ? root.shown.away : null
      readonly property var home: root.shown ? root.shown.home : null
      readonly property var offense: Nfl.isOffense(root.shown, gameCard.away) ? gameCard.away
        : (Nfl.isOffense(root.shown, gameCard.home) ? gameCard.home : null)
      readonly property var defense: gameCard.offense === gameCard.away ? gameCard.home
        : (gameCard.offense === gameCard.home ? gameCard.away : null)

      Item {
        id: gameHead
        width: parent.width
        height: Style.font.caption + Style.space(6)

        Rectangle {
          id: liveDot
          width: 6
          height: 6
          radius: 3
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: root.mode === "live" ? Color.urgent : Color.muted
          opacity: root.mode === "live" ? 1 : 0.6
          border.width: 1
          border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)

          SequentialAnimation {
            id: livePulse
            running: root.mode === "live"
            loops: Animation.Infinite
            NumberAnimation { target: liveDot; property: "opacity"; to: 0.25; duration: 800 }
            NumberAnimation { target: liveDot; property: "opacity"; to: 1; duration: 800 }
            onRunningChanged: if (!running) liveDot.opacity = root.mode === "live" ? 1 : 0.6
          }
        }

        Text {
          anchors.left: liveDot.right
          anchors.leftMargin: Style.space(6)
          anchors.right: networkText.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Nfl.kickoffLine(root.shown)
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 0.5
          font.features: ({ "tnum": 1 })
          elide: Text.ElideRight
        }

        Text {
          id: networkText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.shown ? String(root.shown.network || "") : ""
          color: root.ink
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 0.5
        }
      }

      TeamRow {
        id: awayRow
        width: parent.width
        height: root.heroPx
        anchors.top: gameHead.bottom
        anchors.topMargin: Style.space(4)
        side: gameCard.away
        bright: !Nfl.isLeader(root.shown, gameCard.home)
        ball: root.mode === "live" && Nfl.isOffense(root.shown, gameCard.away)
        favorite: !!(root.shown && root.shown.favorite === "away")
        showRecord: !root.compact
        scorePx: root.heroPx
      }

      TeamRow {
        id: homeRow
        width: parent.width
        height: root.heroPx
        anchors.top: awayRow.bottom
        anchors.topMargin: Style.space(2)
        side: gameCard.home
        bright: !Nfl.isLeader(root.shown, gameCard.away)
        ball: root.mode === "live" && Nfl.isOffense(root.shown, gameCard.home)
        favorite: !!(root.shown && root.shown.favorite === "home")
        showRecord: !root.compact
        scorePx: root.heroPx
      }

      Text {
        id: drive
        width: parent.width
        height: visible ? Style.font.caption + Style.space(4) : 0
        visible: root.mode === "live" && Nfl.driveLine(root.shown) !== ""
        anchors.top: homeRow.bottom
        anchors.topMargin: Style.space(6)
        textFormat: Text.PlainText
        text: Nfl.driveLine(root.shown)
        color: root.ink
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      // The field, drawn from the offence's perspective: their goal on the
      // left, the other one on the right, the ball where the line of
      // scrimmage actually is.
      Item {
        id: field
        width: parent.width
        height: visible ? Style.space(26) : 0
        visible: root.roomy && Nfl.hasField(root.shown)
        anchors.top: drive.bottom
        anchors.topMargin: Style.space(6)

        readonly property real frac: {
          var yard = Nfl.ballYard(root.shown)
          return yard === null ? 0.5 : yard / 100
        }
        readonly property real edge: Style.space(8)
        readonly property real ballX: field.edge + field.frac * (width - field.edge * 2)
        readonly property color ballColor: (root.shown && root.shown.redZone)
          ? Color.urgent : root.sideColor(gameCard.offense)

        Rectangle {
          id: turf
          anchors.fill: parent
          radius: Style.space(6)
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
          border.width: 1
          border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)

          // Yard ticks every 10, the 50 a touch stronger. Enough to read a
          // position off, few enough not to turn the tile into graph paper.
          Repeater {
            model: [10, 20, 30, 40, 50, 60, 70, 80, 90]

            Rectangle {
              required property int modelData
              x: field.edge + (modelData / 100) * (turf.width - field.edge * 2) - width / 2
              width: 1
              height: modelData === 50 ? parent.height * 0.6 : parent.height * 0.36
              anchors.verticalCenter: parent.verticalCenter
              color: root.ink
              opacity: modelData === 50 ? 0.3 : 0.12
            }
          }

          // The ends wear whoever defends them; the offence always drives
          // left to right.
          Rectangle {
            width: Style.space(5)
            height: parent.height - 2
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            radius: 2
            color: root.sideColor(gameCard.offense)
            opacity: 0.55
          }

          Rectangle {
            width: Style.space(5)
            height: parent.height - 2
            anchors.right: parent.right
            anchors.rightMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            radius: 2
            color: root.sideColor(gameCard.defense)
            opacity: 0.55
          }

          Rectangle {
            x: field.ballX - width / 2
            width: 2
            height: parent.height
            color: root.ink
            opacity: 0.6
          }

          Rectangle {
            width: 16
            height: 16
            radius: 8
            x: field.ballX - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: field.ballColor
            opacity: 0.22
          }

          Rectangle {
            width: 9
            height: 9
            radius: 4.5
            x: field.ballX - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: field.ballColor
            border.width: 1
            border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
          }
        }
      }

      // A final looks back, so it gets one line looking forward.
      Text {
        id: nextTeaser
        width: parent.width
        height: visible ? Style.font.caption + Style.space(4) : 0
        visible: root.mode === "final" && !!root.nextGame
        anchors.top: field.bottom
        anchors.topMargin: Style.space(6)
        textFormat: Text.PlainText
        text: {
          if (!root.nextGame) return ""
          var who = Nfl.opponentLine(root.nextGame, Nfl.teamAbbr(root.club))
          var when = Nfl.kickoffLine(root.nextGame)
          return "Next: " + who + (when ? "  ·  " + when : "")
        }
        color: root.ink
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        id: lastPlayText
        width: parent.width
        anchors.top: nextTeaser.visible ? nextTeaser.bottom : field.bottom
        anchors.topMargin: Style.space(6)
        anchors.bottom: parent.bottom
        visible: root.mode === "live" && root.roomy && Nfl.lastPlay(root.shown) !== ""
        clip: true
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: "Last: " + Nfl.lastPlay(root.shown)
        color: root.ink
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 2)
      }
    }

    // ==================================================== between two games
    Item {
      id: nextCard
      anchors.fill: parent
      visible: root.mode === "upcoming" || root.mode === "closed"

      // The next kickoff: who, when, where to watch, and how the last one
      // went, with the opponent's mark big enough to find at a glance.
      Column {
        id: upcomingBlock
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mode === "upcoming"
        spacing: Style.space(4)

        Text {
          width: parent.width
          height: visible ? Style.font.caption + Style.space(4) : 0
          visible: Nfl.weekLine(root.shown) !== ""
          textFormat: Text.PlainText
          text: Nfl.weekLine(root.shown)
          color: root.ink
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 0.8
        }

        Row {
          width: parent.width
          height: Math.max(oppLogo.height, oppName.implicitHeight)
          spacing: Style.space(10)

          Image {
            id: oppLogo
            width: 44
            height: 44
            anchors.verticalCenter: parent.verticalCenter
            source: root.logoFor(Nfl.opponentSide(root.shown))
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: true
            asynchronous: true
          }

          Text {
            id: oppName
            width: parent.width - oppLogo.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            textFormat: Text.PlainText
            text: Nfl.opponentLine(root.shown, Nfl.teamAbbr(root.club))
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: root.cardPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          height: visible ? Style.font.body + Style.space(4) : 0
          visible: text !== ""
          textFormat: Text.PlainText
          text: {
            if (!root.shown) return ""
            var when = Nfl.kickoffLine(root.shown)
            var network = String(root.shown.network || "")
            return network ? when + "  ·  " + network : when
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
          height: visible ? Style.font.caption + Style.space(4) : 0
          visible: root.roomy && root.shown && root.shown.neutral
          textFormat: Text.PlainText
          text: "Neutral site"
          color: root.ink
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          height: visible ? Style.font.caption + Style.space(4) : 0
          visible: root.roomy && !!root.lastGame
          textFormat: Text.PlainText
          text: root.lastGame ? "Last: " + Nfl.resultLine(root.lastGame) : ""
          color: root.ink
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.features: ({ "tnum": 1 })
          elide: Text.ElideRight
        }
      }

      // Nothing left to play. The name says whose season it was; the record
      // and seed say how it went.
      Column {
        id: closedBlock
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mode === "closed"
        spacing: Style.space(4)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "SEASON COMPLETE"
          color: root.ink
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 0.8
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: Nfl.teamLine(root.club)
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: root.cardPx
          font.weight: Font.DemiBold
          fontSizeMode: Text.Fit
          minimumPixelSize: 12
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            if (!root.club) return ""
            var record = String(root.club.record || "")
            var seed = Nfl.seedLine(root.club)
            if (record && seed) return record + "  ·  " + seed + " seed"
            return record || seed
          }
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.Medium
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
          text: Nfl.weekLine(root.games.length ? root.games[0] : null) || "NFL"
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
            readonly property var game: root.games[row.index]
            readonly property bool live: !!(row.game && row.game.live)

            Rectangle {
              id: rowDot
              width: 6
              height: 6
              radius: 3
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: Color.urgent
              opacity: row.live ? 1 : 0

              SequentialAnimation {
                running: row.live
                loops: Animation.Infinite
                NumberAnimation { target: rowDot; property: "opacity"; to: 0.25; duration: 800 }
                NumberAnimation { target: rowDot; property: "opacity"; to: 1; duration: 800 }
                onRunningChanged: if (!running) rowDot.opacity = row.live ? 1 : 0
              }
            }

            Image {
              id: rowLogo
              width: 16
              height: 16
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              source: root.logoFor(row.game && row.game.away)
              fillMode: Image.PreserveAspectFit
              smooth: true
              cache: true
              asynchronous: true
            }

            Text {
              id: rowText
              anchors.left: rowLogo.right
              anchors.leftMargin: Style.space(6)
              anchors.right: rowState.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Nfl.boardLine(row.game)
              color: root.ink
              opacity: row.live ? 1 : 0.7
              font.family: root.fontFamily
              font.pixelSize: root.roomy ? Style.font.body : Style.font.caption
              font.weight: row.live ? Font.DemiBold : Font.Normal
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }

            Text {
              id: rowState
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Nfl.boardState(row.game)
              color: root.ink
              opacity: row.live ? 0.9 : 0.45
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
              onClicked: root.openGame(row.game)
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
        { label: "SEED", value: root.club ? (Nfl.seedLine(root.club) || "—") : "—" }
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
