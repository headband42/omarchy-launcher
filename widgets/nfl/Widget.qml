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

  Item {
    id: body
    anchors.fill: parent
    anchors.margins: Style.space(14)
    visible: root.loaded && !root.failed

    // ------------------------------------------------------------- header
    Item {
      id: header
      width: parent.width
      height: Style.font.caption + Style.space(6)

      Text {
        id: heading
        anchors.left: parent.left
        anchors.right: headerRight.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.eyebrow
        color: root.ink
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        elide: Text.ElideRight
      }

      Row {
        id: headerRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        // A live game breathes, so the tile reads as live before the clock is
        // legible. A finished or scheduled game has no dot.
        Rectangle {
          id: pulse
          width: 6
          height: 6
          radius: 3
          anchors.verticalCenter: parent.verticalCenter
          visible: root.shown && root.shown.live
          color: root.ink
          opacity: 0.5

          SequentialAnimation on opacity {
            running: pulse.visible
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
          }
        }

        Text {
          id: statusText
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: {
            if (root.shown && (root.shown.live || root.shown.finished)) return String(root.shown.time || "")
            if (root.mode === "upcoming") return "NEXT GAME"
            if (root.mode === "closed") return "SEASON OVER"
            if (root.mode === "board") return root.games.length + " GAMES"
            return root.status
          }
          color: root.ink
          opacity: 0.85
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.features: ({ "tnum": 1 })
          elide: Text.ElideRight
        }
      }
    }

    // ------------------------------------------------------- live or final
    Item {
      id: scoreCard
      width: parent.width
      height: parent.height - header.height - statRow.height - Style.space(10)
      visible: root.mode === "live" || root.mode === "final"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)

      Row {
        id: scoreRow
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: Style.space(4)
        spacing: Style.space(4)

        Item {
          id: awaySide
          width: (scoreRow.width - scoreRow.spacing * 3) / 2
          height: scoreRow.height
          readonly property var side: root.shown ? root.shown.away : null

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Nfl.teamAbbr(awaySide.side)
              color: root.ink
              opacity: Nfl.isLeader(root.shown, awaySide.side) ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: 0.5
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Nfl.sideScore(awaySide.side)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: root.heroPx
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: root.roomy
              textFormat: Text.PlainText
              text: String((awaySide.side && awaySide.side.nickname) || "")
              color: root.ink
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: !root.compact
              textFormat: Text.PlainText
              text: String((awaySide.side && awaySide.side.record) || "")
              color: root.ink
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }
          }
        }

        Item {
          width: Style.space(30)
          height: scoreRow.height

          Column {
            anchors.centerIn: parent
            spacing: Style.space(4)

            // The ball marker. Whoever is on offense is the one thing on the
            // tile that a baseball score cannot express.
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: 7
              height: 7
              radius: 3.5
              visible: !!(root.shown && root.shown.possession)
              color: root.ink
              opacity: 0.75
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: root.shown && root.shown.neutral ? "NEU" : "@"
              color: root.ink
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.shown && root.shown.network
              textFormat: Text.PlainText
              text: root.shown ? String(root.shown.network || "") : ""
              color: root.ink
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.weight: Font.DemiBold
            }
          }
        }

        Item {
          id: homeSide
          width: (scoreRow.width - scoreRow.spacing * 3) / 2
          height: scoreRow.height
          readonly property var side: root.shown ? root.shown.home : null

          Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Style.space(1)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Nfl.teamAbbr(homeSide.side)
              color: root.ink
              opacity: Nfl.isLeader(root.shown, homeSide.side) ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: 0.5
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Nfl.sideScore(homeSide.side)
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: root.heroPx
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              visible: root.roomy
              textFormat: Text.PlainText
              text: String((homeSide.side && homeSide.side.nickname) || "")
              color: root.ink
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              visible: !root.compact
              textFormat: Text.PlainText
              text: String((homeSide.side && homeSide.side.record) || "")
              color: root.ink
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 2)
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }
          }
        }
      }

      // The drive. Quarter, down, distance, and where the ball is: the four
      // numbers that turn a pair of scores into a game.
      Column {
        id: drive
        width: parent.width
        anchors.bottom: parent.bottom
        spacing: Style.space(4)

        Rectangle {
          width: parent.width
          height: Style.space(30)
          radius: Style.space(8)
          visible: Nfl.situationLine(root.shown) !== ""
          color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.09)

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.shown ? String(root.shown.downDistance || "") : ""
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }

            Rectangle {
              width: 1
              height: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
              color: root.ink
              opacity: 0.18
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, parent.width - x - parent.parent.leftMargin)
              textFormat: Text.PlainText
              text: root.shown ? String(root.shown.ball || "") : ""
              color: root.ink
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.letterSpacing: 0.5
              elide: Text.ElideRight
            }
          }
        }

        Text {
          width: parent.width
          visible: root.roomy && Nfl.lastPlay(root.shown) !== ""
          textFormat: Text.PlainText
          text: Nfl.lastPlay(root.shown)
          color: root.ink
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, Style.font.caption - 2)
          maximumLineCount: 2
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
        }
      }
    }

    // ------------------------------------------------------------- next up
    Item {
      id: nextCard
      width: parent.width
      height: parent.height - header.height - statRow.height - Style.space(10)
      visible: root.mode === "upcoming" || root.mode === "closed"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(7)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.mode === "closed"
            ? (root.club ? root.club.city + " " + root.club.nickname : "NFL")
            : Nfl.opponentLine(root.nextGame, Nfl.teamAbbr(root.club))
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: root.mode === "closed" ? root.heroPx : root.heroPx
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

    // ------------------------------------------------------------ the slate
    Column {
      id: boardList
      width: parent.width
      height: parent.height - header.height - Style.space(8)
      visible: root.mode === "board"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      spacing: 0

      Repeater {
        model: root.boardCount

        Item {
          required property int index
          width: boardList.width
          height: boardList.height / Math.max(1, root.boardCount)

          Text {
            id: rowText
            anchors.left: parent.left
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
            visible: index < root.boardCount - 1
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

    // ------------------------------------------------------------ the club
    Row {
      id: statRow
      width: parent.width
      height: Style.space(34)
      anchors.bottom: parent.bottom
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

  // Above the score text, under the per-row areas on the slate. A click on
  // the club card opens the game being shown; a click on a slate row opens
  // that row's game.
  MouseArea {
    id: cardLink
    z: 2
    anchors.fill: body
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
