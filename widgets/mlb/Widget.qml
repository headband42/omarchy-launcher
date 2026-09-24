import QtQuick
import Quickshell.Io
import qs.Commons
import "colors.js" as Colors

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

  readonly property int teamId: {
    var settings = root.tile && root.tile.settings
    var n = Number(settings && settings.teamId)
    if (!isFinite(n) || n <= 0) return 0
    return Math.round(n)
  }
  // Team colors restyle this tile only. The launcher around it stays on the system theme.
  readonly property bool teamColors: {
    var settings = root.tile && root.tile.settings
    return !!(settings && settings.teamColors) && root.teamId > 0
  }
  readonly property var palette: root.teamColors ? Colors.palette(root.teamId) : null
  readonly property color ink: root.palette ? root.palette.text : root.foreground
  readonly property color mark: root.palette ? root.palette.accent : Color.urgent
  // Text on an inverted box: the tile fill, or the menu fill without team colors.
  readonly property color paper: root.palette ? root.palette.background : Color.menu.background
  readonly property string mode: String((root.sample && root.sample.mode) || "")
  readonly property bool failed: root.loaded && !!root.sample && root.sample.ok === false
  readonly property var shown: root.sample && root.sample.focus ? root.sample.focus : null
  readonly property var games: {
    var rows = root.sample && root.sample.games
    return rows && rows.length ? rows : []
  }
  readonly property var nextGame: root.sample && root.sample.next ? root.sample.next : null
  readonly property var standings: root.sample && root.sample.standings ? root.sample.standings : null
  // Standings switcher selection. Empty follows the favorite club: its
  // league and division. A background poll keeps a tab the user picked.
  property string standLeague: ""
  property var standTable
  property string standKey: ""
  readonly property int pollMs: {
    var n = Number(root.sample && root.sample.pollMs)
    if (!isFinite(n) || n < 15000) return 60000
    if (n > 300000) return 300000
    return Math.round(n)
  }
  readonly property string tileUrl: {
    if (root.mode === "board") return ""
    if ((root.mode === "live" || root.mode === "final") && root.shown && root.shown.gameday)
      return String(root.shown.gameday)
    if (root.nextGame && root.nextGame.gameday) return String(root.nextGame.gameday)
    return ""
  }
  readonly property int abbrW: Style.space(36)
  readonly property int rheW: Style.space(15)
  readonly property int inningSlots: {
    var labels = root.shown && root.shown.labels
    return labels && labels.length ? labels.length : 0
  }
  readonly property bool wideInnings: {
    var labels = root.shown && root.shown.labels
    if (!labels) return false
    for (var i = 0; i < labels.length; i++) {
      if (String(labels[i]).length > 1) return true
    }
    return false
  }
  readonly property int cellW: {
    if (root.inningSlots < 1) return 0
    var avail = root.width - Style.space(20) - root.abbrW - root.rheW * 3
    if (avail <= 0) return 0
    return Math.floor(avail / root.inningSlots)
  }
  // Between games the division table needs the room, so the inning line waits
  // for a taller tile. A live game has no table, so the line can use the width.
  // A final always shows the labeled grid: the header row names every column.
  readonly property bool showLine: {
    if (!(root.shown && root.shown.hasLine && root.cellW >= (root.wideInnings ? Style.space(16) : Style.space(11))))
      return false
    if (root.mode === "live") return true
    if (root.mode === "final") return true
    return root.height >= Style.space(260)
  }
  readonly property var lineRows: {
    var game = root.shown || {}
    var away = game.away || {}
    var home = game.home || {}
    return [
      { header: true, abbr: "", cells: game.labels || [], r: "R", h: "H", e: "E", strong: false },
      { header: false, abbr: String(away.abbr || ""), cells: away.innings || [], r: String(away.score || ""), h: String(away.hits || ""), e: String(away.errors || ""), strong: game.favorite === "away" },
      { header: false, abbr: String(home.abbr || ""), cells: home.innings || [], r: String(home.score || ""), h: String(home.hits || ""), e: String(home.errors || ""), strong: game.favorite === "home" }
    ]
  }
  readonly property bool boardNames: {
    if (root.mode !== "board" || root.games.length < 1 || boardList.height < 1) return false
    return boardList.height / root.games.length >= Style.font.caption * 2 + Style.space(8)
  }
  readonly property int boardFont: root.boardNames ? Style.font.body : Style.font.caption
  readonly property bool liveFocus: root.mode === "live" && !!root.shown
  readonly property var liveLeft: (root.shown && root.shown.left) || ({})
  readonly property var liveRight: (root.shown && root.shown.right) || ({})
  readonly property string liveMark: String((root.shown && root.shown.mark) || "")
  readonly property int liveInner: {
    var w = liveBoard.width
    var h = liveBoard.height
    if (w < 1 || h < 1) return Math.max(0, Math.min(root.width, root.height) - Style.space(16))
    return Math.round(Math.min(w, h))
  }
  readonly property int liveGap: Math.max(Style.space(4), Math.round(root.liveInner * 0.02))
  readonly property int liveScorePx: Math.max(Style.space(22), Math.round(root.liveInner * 0.16))
  readonly property int liveLogo: Math.max(Style.space(16), Math.round(root.liveScorePx * 0.62))
  readonly property int liveBalls: {
    var n = Number(root.shown && root.shown.balls)
    if (!isFinite(n) || n < 0) return 0
    return Math.min(3, Math.round(n))
  }
  readonly property int liveStrikes: {
    var n = Number(root.shown && root.shown.strikes)
    if (!isFinite(n) || n < 0) return 0
    return Math.min(2, Math.round(n))
  }
  readonly property int liveOuts: {
    var n = Number(root.shown && root.shown.outs)
    if (!isFinite(n) || n < 0) return 0
    return Math.min(3, Math.round(n))
  }

  // The club beside its score. The live view shows the club record under the
  // name; the post-game view hides it because the box score carries the result.
  component SideBlock: Row {
    id: side
    property var club: ({})
    property bool alignRight: false
    property bool showRecord: true
    layoutDirection: alignRight ? Qt.RightToLeft : Qt.LeftToRight
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: scoreGauge.implicitWidth
      horizontalAlignment: side.alignRight ? Text.AlignRight : Text.AlignLeft
      textFormat: Text.PlainText
      text: String((side.club && side.club.score) || "")
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: root.liveScorePx
      font.weight: Font.DemiBold
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.max(1, Style.space(1))

      Row {
        id: nameRow
        layoutDirection: side.alignRight ? Qt.RightToLeft : Qt.LeftToRight
        spacing: Style.space(5)

        Image {
          anchors.verticalCenter: parent.verticalCenter
          width: root.liveLogo
          height: root.liveLogo
          source: root.logoSource(side.club && side.club.id)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: width
          sourceSize.height: height
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String((side.club && side.club.abbr) || "")
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Math.max(Style.font.title, Math.round(root.liveLogo * 0.5))
          font.weight: root.clubStrong(side.club) ? Font.DemiBold : Font.Medium
        }
      }

      Text {
        width: nameRow.implicitWidth
        visible: side.showRecord && !!(side.club && side.club.record)
        horizontalAlignment: side.alignRight ? Text.AlignRight : Text.AlignLeft
        textFormat: Text.PlainText
        text: side.club && side.club.record ? "(" + String(side.club.record) + ")" : ""
        color: root.ink
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // One standings switcher segment. The caller spans it across the row;
  // the box fills the whole segment and the MouseArea covers the box, so
  // a click anywhere on it switches tables. The pick inverts ink on paper.
  component StandTab: Item {
    id: tab
    property string label: ""
    property bool selected: false
    signal tapped

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: tab.selected ? root.ink : "transparent"
      border.width: tab.selected ? 0 : Math.max(1, Style.space(1))
      border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: tab.label
      color: tab.selected ? root.paper : root.ink
      opacity: tab.selected ? 1 : 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: tab.selected ? Font.DemiBold : Font.Medium
      elide: Text.ElideRight
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.tapped()
    }
  }

  function standingsUrl() {
    return "https://www.mlb.com/standings"
  }

  function nextGameUrl() {
    return String((root.nextGame && root.nextGame.gameday) || "")
  }

  function standLeagues() {
    var rows = root.standings && root.standings.leagues
    return rows && rows.length ? rows : []
  }

  function standDefaults() {
    var st = root.standings || {}
    return { league: String(st.defaultLeague || ""), table: st.defaultTable }
  }

  function standLeagueObj() {
    var leagues = root.standLeagues()
    var want = root.standLeague || root.standDefaults().league
    for (var i = 0; i < leagues.length; i++) {
      if (String(leagues[i].id) === want) return leagues[i]
    }
    return leagues.length ? leagues[0] : null
  }

  function standTableObj() {
    var league = root.standLeagueObj()
    if (!league || !league.tables || !league.tables.length) return null
    var tables = league.tables
    var want = root.standTable
    if (want === undefined || want === null || want === "") {
      var dflt = root.standDefaults()
      want = String(league.id) === dflt.league ? dflt.table : tables[0].id
    }
    for (var j = 0; j < tables.length; j++) {
      if (tables[j].id === want) return tables[j]
    }
    return tables[0]
  }

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

  function logoSource(id) {
    var n = Number(id)
    if (!isFinite(n) || n <= 0) return ""
    return Qt.resolvedUrl("logos/" + Math.round(n) + ".png")
  }

  function openLink(url) {
    var value = String(url || "").trim()
    if (value.indexOf("https://www.mlb.com/") !== 0 && value.indexOf("https://mlb.com/") !== 0)
      return
    // Launch before the launcher closes. The old click stopped at a host
    // signal and the browser never started.
    Util.execArgv(["omarchy-launch-webapp", value])
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  function baseMarks(bases) {
    var marks = bases || []
    function bit(i) { return marks[i] ? "●" : "○" }
    return bit(0) + " " + bit(1) + " " + bit(2)
  }

  function boardGame(index) {
    if (index < 0 || index >= root.games.length) return ({})
    return root.games[index] || ({})
  }

  function sideStrong(side) {
    return !!(root.shown && root.shown.favorite === side)
  }

  function clubStrong(club) {
    if (!club || !root.shown || !root.shown.favorite) return false
    var side = root.shown.favorite === "home" ? root.shown.home : root.shown.away
    return !!(side && club.id === side.id)
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
        root.sample = {
          ok: false, mode: "empty", banner: "MLB", error: "Scores unavailable",
          focus: null, games: [], next: null
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
    z: 0
    anchors.fill: parent
    radius: Style.cornerRadius
    visible: root.palette
    color: root.palette ? root.palette.background : "transparent"
  }

  Component.onCompleted: root.refresh()
  onVisibleChanged: if (visible) root.refresh()
  onTeamIdChanged: {
    root.sample = ({})
    root.haveScore = false
    root.loaded = false
    if (root.visible) root.refresh()
  }

  // A new favorite club re-seeds the switcher. Poll refreshes keep the pick:
  // the key only changes when the default league or division does.
  onStandingsChanged: {
    var dflt = root.standDefaults()
    var key = dflt.league + "|" + String(dflt.table)
    if (root.standKey !== key) {
      root.standKey = key
      root.standLeague = ""
      root.standTable = undefined
    }
  }

  // Above the tile-wide Gameday catcher below, so the standings tabs get
  // first shot at a click. Empty chrome still falls through to it: plain
  // Text and Images never take a click.
  Item {
    id: page
    z: 3
    anchors.fill: parent
    anchors.margins: Style.space(8)

    Column {
      id: message
      z: 1
      visible: root.mode !== "board" && root.mode !== "live" && root.mode !== "final"
      width: parent.width
      spacing: Style.space(2)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "\uf433"
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        visible: !root.loaded || root.failed
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.loaded ? "Scores unavailable" : "Loading scores…"
        color: root.ink
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: root.loaded && !root.failed && root.mode === "empty"
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "No live games"
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
      }

      Text {
        visible: root.loaded && !root.failed && root.nextGame && (root.mode === "empty" || root.mode === "upcoming")
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.nextGame ? String(root.nextGame.kicker || "") : ""
        color: root.ink
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.loaded && !root.failed && root.nextGame && (root.mode === "empty" || root.mode === "upcoming")
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.nextGame ? String(root.nextGame.when || "") : ""
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Text {
        visible: root.loaded && !root.failed && root.nextGame && (root.mode === "empty" || root.mode === "upcoming")
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.nextGame ? String(root.nextGame.where || "") : ""
        color: root.ink
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    Column {
      id: board
      z: 1
      visible: root.mode === "board"
      anchors.fill: parent
      spacing: Style.space(4)

      Item {
        id: boardHeader
        width: parent.width
        height: Style.font.caption + Style.space(2)

        Rectangle {
          id: boardDot
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: root.mark
        }

        Text {
          anchors.left: boardDot.right
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: {
            var banner = String((root.sample && root.sample.banner) || "Live")
            return banner + (root.games.length ? " · " + root.games.length : "")
          }
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          elide: Text.ElideRight
        }
      }

      Item {
        id: boardList
        width: parent.width
        height: Math.max(0, parent.height - boardHeader.height - board.spacing)

        Repeater {
          model: root.games.length

          Item {
            required property int index
            property var game: root.boardGame(index)
            width: boardList.width
            height: root.games.length > 0 ? boardList.height / root.games.length : 0

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: rowMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"
            }

            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Item {
                width: parent.width
                height: scoreLine.implicitHeight

                Text {
                  id: scoreLine
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(game.rowTitle || "")
                  color: root.ink
                  font.family: root.fontFamily
                  font.pixelSize: root.boardFont
                  font.weight: Font.Medium
                }

                Text {
                  id: baseLine
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.baseMarks(game.bases)
                  color: root.ink
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: !root.boardNames
                  anchors.left: scoreLine.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: baseLine.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(game.rowDetail || "") + (game.rowNames ? "  " + game.rowNames : "")
                  color: root.ink
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Text {
                visible: root.boardNames
                width: parent.width
                textFormat: Text.PlainText
                text: String(game.rowDetail || "") + (game.rowNames ? "  " + game.rowNames : "")
                color: root.ink
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openLink(game.gameday)
            }
          }
        }
      }
    }

    Item {
      id: liveBoard
      z: 1
      visible: root.liveFocus
      anchors.fill: parent

      Text {
        id: scoreGauge
        visible: false
        text: "00"
        font.family: root.fontFamily
        font.pixelSize: root.liveScorePx
        font.weight: Font.DemiBold
      }

      Item {
        id: liveHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(leftBlock.height, rightBlock.height, markText.implicitHeight)

        SideBlock {
          id: leftBlock
          anchors.left: parent.left
          anchors.top: parent.top
          club: root.liveLeft
        }

        Text {
          id: markText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.liveMark
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
        }

        SideBlock {
          id: rightBlock
          anchors.right: parent.right
          anchors.top: parent.top
          alignRight: true
          club: root.liveRight
        }
      }

      Text {
        id: inningLive
        anchors.top: liveHeader.bottom
        anchors.topMargin: root.liveGap
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: String((root.shown && root.shown.status) || "")
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Item {
        id: lower
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: lineArea.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(4)

          Item {
            id: liveCount
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            readonly property int side: Math.max(Style.space(44), Math.min(Style.space(64), Math.round(root.liveInner * 0.2)))
            height: side

        component CountGroup: Row {
          id: group
          property string label: ""
          property int slots: 3
          property int filled: 0
          property color lamp: root.ink
          readonly property int pip: Style.space(7)
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(46)
            textFormat: Text.PlainText
            text: group.label
            color: root.ink
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Repeater {
            model: group.slots
            Rectangle {
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              width: group.pip
              height: group.pip
              radius: width / 2
              border.width: Math.max(1, Style.space(1))
              border.color: group.lamp
              color: index < group.filled ? group.lamp : "transparent"
              opacity: index < group.filled ? 1 : 0.4
            }
          }
        }

          Item {
            id: liveDiamond
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -parent.width / 4
            anchors.verticalCenter: parent.verticalCenter
            // Each mark is a square turned 45°, so the points face up, down,
            // left, and right. First and third meet side to side. Second sits
            // on the edges above them. An equilateral layout leaves second short.
            property var bases: (root.shown && root.shown.bases) || []
            property real base: Math.max(Style.space(9), liveCount.side / (2 * Math.sqrt(2)))
            property real reach: base / Math.sqrt(2)
            property real clusterW: reach * 4
            property real clusterH: reach * 3
            property real originX: Math.max(0, (width - clusterW) / 2)
            property real originY: Math.max(0, (height - clusterH) / 2)
            property real thirdX: originX + reach
            property real thirdY: originY + reach * 2
            property real firstX: originX + reach * 3
            property real firstY: thirdY
            property real secondX: originX + reach * 2
            property real secondY: originY + reach
            width: liveCount.side
            height: liveCount.side

            Rectangle {
              x: liveDiamond.secondX - width / 2
              y: liveDiamond.secondY - height / 2
              width: liveDiamond.base
              height: liveDiamond.base
              radius: 0
              rotation: 45
              color: liveDiamond.bases[1] ? root.ink : "transparent"
              border.color: root.ink
              border.width: Math.max(1, Style.space(1))
            }

            Rectangle {
              x: liveDiamond.thirdX - width / 2
              y: liveDiamond.thirdY - height / 2
              width: liveDiamond.base
              height: liveDiamond.base
              radius: 0
              rotation: 45
              color: liveDiamond.bases[2] ? root.ink : "transparent"
              border.color: root.ink
              border.width: Math.max(1, Style.space(1))
            }

            Rectangle {
              x: liveDiamond.firstX - width / 2
              y: liveDiamond.firstY - height / 2
              width: liveDiamond.base
              height: liveDiamond.base
              radius: 0
              rotation: 45
              color: liveDiamond.bases[0] ? root.ink : "transparent"
              border.color: root.ink
              border.width: Math.max(1, Style.space(1))
            }
          }

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: parent.width / 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            CountGroup {
              label: "Balls"
              slots: 3
              filled: root.liveBalls
              lamp: root.ink
            }
            CountGroup {
              label: "Strikes"
              slots: 2
              filled: root.liveStrikes
              lamp: root.ink
            }
            CountGroup {
              label: "Outs"
              slots: 3
              filled: root.liveOuts
              lamp: root.mark
            }
          }
          }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: liveCount.bottom
          anchors.bottom: parent.bottom

          Column {
            id: liveNames
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.max(1, Style.space(2))

            Text {
              width: parent.width
              visible: !!(root.shown && root.shown.batterLine)
              textFormat: Text.PlainText
              text: root.shown ? String(root.shown.batterLine || "") : ""
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: !!(root.shown && root.shown.pitcherLine)
              textFormat: Text.PlainText
              text: root.shown ? String(root.shown.pitcherLine || "") : ""
              color: root.ink
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }
      }

      Item {
        id: lineArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: inningLive.bottom
        anchors.topMargin: root.liveGap
        height: (liveLine.visible ? liveLine.height : 0) + (tvLine.visible ? tvLine.implicitHeight + Style.space(2) : 0)

        Column {
          id: liveLine
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: 0
          readonly property int slots: root.inningSlots
          readonly property int nameW: Style.space(34)
          readonly property int statW: Style.space(14)
          readonly property int cellW: slots > 0 ? Math.max(0, Math.floor((width - nameW - statW * 3) / slots)) : 0
          readonly property int rowH: Style.font.caption + Style.space(3)
          visible: !!(root.shown && root.shown.hasLine && cellW >= Style.space(8))

          Repeater {
            model: root.lineRows

            Item {
              id: lineItem
              required property var modelData
              property var row: modelData
              width: liveLine.width
              height: liveLine.rowH

              Text {
                width: liveLine.nameW
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: String(row.abbr || "")
                color: root.ink
                opacity: row.header ? 0.45 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: row.strong ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
              }

              Repeater {
                model: liveLine.slots

                Text {
                  required property int index
                  x: liveLine.nameW + index * liveLine.cellW
                  width: liveLine.cellW
                  height: lineItem.height
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  text: {
                    var cells = row.cells || []
                    if (index >= cells.length || cells[index] === undefined || cells[index] === null) return ""
                    return String(cells[index])
                  }
                  color: root.ink
                  opacity: row.header ? 0.45 : 1
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Row {
                anchors.right: parent.right
                height: parent.height

                Text {
                  width: liveLine.statW
                  height: lineItem.height
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  text: String(row.r || "")
                  color: root.ink
                  opacity: row.header ? 0.45 : 1
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: row.header ? Font.Medium : Font.DemiBold
                }

                Text {
                  width: liveLine.statW
                  height: lineItem.height
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  text: String(row.h || "")
                  color: root.ink
                  opacity: row.header ? 0.45 : 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  width: liveLine.statW
                  height: lineItem.height
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  text: String(row.e || "")
                  color: root.ink
                  opacity: row.header ? 0.45 : 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Text {
          id: tvLine
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: liveLine.visible ? liveLine.bottom : parent.top
          anchors.topMargin: liveLine.visible ? Style.space(2) : 0
          horizontalAlignment: Text.AlignRight
          visible: text.length > 0
          textFormat: Text.PlainText
          text: String((root.shown && root.shown.tv) || "")
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
    Column {
      id: score
      z: 1
      visible: root.mode === "final"
      width: parent.width
      spacing: Style.space(2)
      y: Math.max(0, Math.round((parent.height - height) / 2))

      Item {
        id: finalHeader
        width: parent.width
        height: Math.max(finalLeft.height, finalRight.height, finalMark.implicitHeight)

        SideBlock {
          id: finalLeft
          anchors.left: parent.left
          anchors.top: parent.top
          showRecord: false
          club: root.liveLeft
        }

        Text {
          id: finalMark
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.liveMark
          color: root.ink
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
        }

        SideBlock {
          id: finalRight
          anchors.right: parent.right
          anchors.top: parent.top
          alignRight: true
          showRecord: false
          club: root.liveRight
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: String((root.shown && root.shown.status) || "")
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Column {
        id: lineCol
        visible: root.showLine
        width: parent.width
        spacing: 0

        Repeater {
          model: root.lineRows

          Item {
            id: lineItem
            required property var modelData
            property var row: modelData
            width: lineCol.width
            height: Style.font.caption + Style.space(3)

            Text {
              width: root.abbrW
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: String(row.abbr || "")
              color: root.ink
              opacity: row.header ? 0.45 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: row.strong ? Font.DemiBold : Font.Medium
              elide: Text.ElideRight
            }

            Repeater {
              model: root.inningSlots

              Text {
                required property int index
                x: root.abbrW + index * root.cellW
                width: root.cellW
                height: lineItem.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: {
                  var cells = row.cells || []
                  if (index >= cells.length || cells[index] === undefined || cells[index] === null) return ""
                  return String(cells[index])
                }
                color: root.ink
                opacity: row.header ? 0.45 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: row.strong ? Font.DemiBold : Font.Normal
              }
            }

            Row {
              anchors.right: parent.right
              height: parent.height

              Text {
                width: root.rheW
                height: lineItem.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: String(row.r || "")
                color: root.ink
                opacity: row.header ? 0.45 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: row.header ? Font.Medium : (row.strong ? Font.DemiBold : Font.Medium)
              }

              Text {
                width: root.rheW
                height: lineItem.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: String(row.h || "")
                color: root.ink
                opacity: row.header ? 0.45 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: root.rheW
                height: lineItem.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: String(row.e || "")
                color: root.ink
                opacity: row.header ? 0.45 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Column {
        visible: root.shown && !root.showLine
        width: parent.width
        spacing: Style.space(1)

        Item {
          width: parent.width
          height: Style.font.heading + Style.space(2)

          Image {
            id: awayLogo
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            source: root.logoSource(root.shown && root.shown.away ? root.shown.away.id : 0)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: width
            sourceSize.height: height
          }

          Text {
            anchors.left: awayLogo.right
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.away && root.shown.away.abbr) || "")
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.sideStrong("away") ? Font.DemiBold : Font.Medium
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.away && root.shown.away.score) || "")
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }
        }

        Item {
          width: parent.width
          height: Style.font.heading + Style.space(2)

          Image {
            id: homeLogo
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            source: root.logoSource(root.shown && root.shown.home ? root.shown.home.id : 0)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: width
            sourceSize.height: height
          }

          Text {
            anchors.left: homeLogo.right
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.home && root.shown.home.abbr) || "")
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.sideStrong("home") ? Font.DemiBold : Font.Medium
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.home && root.shown.home.score) || "")
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            var away = (root.shown && root.shown.away) || {}
            var home = (root.shown && root.shown.home) || {}
            return "H " + String(away.hits || "–") + "–" + String(home.hits || "–")
              + "   E " + String(away.errors || "–") + "–" + String(home.errors || "–")
          }
          color: root.ink
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: !!(root.shown && root.shown.live && root.shown.countLine)
        width: parent.width
        textFormat: Text.PlainText
        text: root.shown ? String(root.shown.countLine || "") : ""
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Text {
        visible: !!(root.shown && root.shown.batterLine)
        width: parent.width
        textFormat: Text.PlainText
        text: root.shown ? String(root.shown.batterLine || "") : ""
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        visible: !!(root.shown && root.shown.pitcherLine)
        width: parent.width
        textFormat: Text.PlainText
        text: root.shown ? String(root.shown.pitcherLine || "") : ""
        color: root.ink
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        visible: !!(root.shown && root.shown.decisionLine)
        width: parent.width
        textFormat: Text.PlainText
        text: root.shown ? String(root.shown.decisionLine || "") : ""
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Column {
        id: standCol
        visible: !!(root.standLeagueObj() && root.standTableObj())
        width: parent.width
        spacing: Style.space(2)

        Row {
          id: leagueRow
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.standLeagues().length

            StandTab {
              required property int index
              property var league: root.standLeagues()[index]
              width: (leagueRow.width - (root.standLeagues().length - 1) * leagueRow.spacing) / root.standLeagues().length
              height: Style.font.caption + Style.space(8)
              label: String(league.label || league.id)
              selected: !!(root.standLeagueObj() && root.standLeagueObj().id === league.id)
              onTapped: {
                root.standLeague = String(league.id)
                root.standTable = undefined
              }
            }
          }
        }

        Row {
          id: tableRow
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.standLeagueObj() ? root.standLeagueObj().tables.length : 0

            StandTab {
              required property int index
              property var table: root.standLeagueObj().tables[index]
              property int slots: root.standLeagueObj().tables.length
              width: (tableRow.width - (slots - 1) * tableRow.spacing) / slots
              height: Style.font.caption + Style.space(8)
              label: String(table.label || "")
              selected: !!(root.standTableObj() && root.standTableObj().id === table.id)
              onTapped: root.standTable = table.id
            }
          }
        }

        Text {
          id: winGauge
          visible: false
          textFormat: Text.PlainText
          text: "000"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }

        Text {
          id: lossGauge
          visible: false
          textFormat: Text.PlainText
          text: "000"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }

        Text {
          id: gbGauge
          visible: false
          textFormat: Text.PlainText
          text: "+00.0"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }

        Item {
          id: standHead
          width: parent.width
          height: Style.font.caption + Style.space(2)

          Row {
            anchors.right: parent.right
            height: parent.height
            spacing: Style.space(8)

            Text {
              width: winGauge.implicitWidth
              height: parent.height
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: "W"
              color: root.ink
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
            }

            Text {
              width: lossGauge.implicitWidth
              height: parent.height
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: "L"
              color: root.ink
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
            }

            Text {
              width: gbGauge.implicitWidth
              height: parent.height
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: "GB"
              color: root.ink
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
            }
          }
        }

        Repeater {
          model: root.standTableObj() && root.standTableObj().rows ? root.standTableObj().rows.length : 0

          Item {
            required property int index
            property var club: root.standTableObj().rows[index]
            width: standCol.width
            height: Style.font.caption + Style.space(4)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
              visible: club.favorite
            }

            Image {
              id: standingLogo
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(14)
              height: Style.space(14)
              source: root.logoSource(club.id)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: width
              sourceSize.height: height
            }

            Text {
              anchors.left: standingLogo.right
              anchors.leftMargin: Style.space(4)
              anchors.right: standNumbers.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(club.abbr || "")
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: club.favorite ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
            }

            Row {
              id: standNumbers
              anchors.right: parent.right
              height: parent.height
              spacing: Style.space(8)

              Text {
                width: winGauge.implicitWidth
                height: parent.height
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: club.wins === undefined ? "" : String(club.wins)
                color: root.ink
                opacity: club.favorite ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: club.favorite ? Font.DemiBold : Font.Normal
              }

              Text {
                width: lossGauge.implicitWidth
                height: parent.height
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: club.losses === undefined ? "" : String(club.losses)
                color: root.ink
                opacity: club.favorite ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: club.favorite ? Font.DemiBold : Font.Normal
              }

              Text {
                width: gbGauge.implicitWidth
                height: parent.height
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: String(club.gb || "")
                color: root.ink
                opacity: club.favorite ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: club.favorite ? Font.DemiBold : Font.Normal
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openLink(root.standingsUrl())
            }
          }
        }
      }

      Item {
        id: nextBlock
        visible: root.mode === "final" && root.nextGame
        width: parent.width
        height: visible ? nextLine1.height + nextLine2.height : 0

        // The block opens the upcoming game, not the final above it.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: root.nextGameUrl().length > 0
          onClicked: root.openLink(root.nextGameUrl())
        }

        Item {
          id: nextLine1
          width: parent.width
          height: nextWhen.implicitHeight

          Text {
            id: nextWhen
            anchors.left: parent.left
            anchors.right: nextTv.visible ? nextTv.left : parent.right
            anchors.rightMargin: nextTv.visible ? Style.space(6) : 0
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.nextGame ? (String(root.nextGame.kicker || "Next") + "  " + String(root.nextGame.when || "")) : ""
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            id: nextTv
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: text.length > 0
            textFormat: Text.PlainText
            text: String((root.nextGame && root.nextGame.tv) || "")
            color: root.ink
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Item {
          id: nextLine2
          anchors.top: nextLine1.bottom
          width: parent.width
          height: nextWhere.implicitHeight

          Text {
            id: nextWhere
            anchors.left: parent.left
            anchors.right: nextArms.visible ? nextArms.left : parent.right
            anchors.rightMargin: nextArms.visible ? Style.space(6) : 0
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.nextGame ? String(root.nextGame.where || "") : ""
            color: root.ink
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            id: nextArms
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: text.length > 0
            textFormat: Text.PlainText
            text: String((root.nextGame && root.nextGame.pitchers) || "")
            color: root.ink
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Above the score text, under the per-game areas on the live slate.
  // A click here opens the game on Gameday instead of the slot's Opens link.
  MouseArea {
    z: 2
    anchors.fill: parent
    enabled: root.mode !== "board" && root.tileUrl.length > 0
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.openLink(root.tileUrl)
  }
}
