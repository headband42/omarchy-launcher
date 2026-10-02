import QtQuick
import qs.Commons
import "../_kit"
import "scores.js" as Scores

// One league's games from ESPN, and with a team picked, that team's game on
// top: live, else a fresh final, else the next one. A game opens on ESPN.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowMs: Date.now()

  readonly property var settings: root.tile && root.tile.settings ? root.tile.settings : ({})
  readonly property string league: Scores.leagueOf(root.settings, "nba")
  readonly property string team: Scores.teamOf(root.settings)
  readonly property bool darkTheme: Scores.isDark(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b)
  readonly property bool h24: {
    var format = Qt.locale().timeFormat(Locale.ShortFormat)
    return format.indexOf("AP") < 0 && format.indexOf("ap") < 0 && format.indexOf("A") < 0 && format.indexOf("a") < 0
  }
  readonly property var featured: root.sample ? root.sample.featured : null
  readonly property var games: root.sample && Array.isArray(root.sample.games) ? root.sample.games : []

  function open(game) {
    if (game && game.link && root.host && root.host.openLink) root.host.openLink(String(game.link))
  }

  Poller {
    script: Qt.resolvedUrl("scores.py")
    args: root.team ? ["--league", root.league, "--team", root.team] : ["--league", root.league]
    interval: root.sample && root.sample.pollMs ? Number(root.sample.pollMs) : 300000
    active: root.visible
    onSampled: function(data) { if (data) root.sample = data }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.visible
    onTriggered: root.nowMs = Date.now()
  }

  // Two lines, away over home, with the status on the right.
  component GameRow: Item {
    id: gameRow
    property var game: ({})
    property real lineSize: Style.font.bodySmall
    property real logoSize: Style.space(16)
    readonly property bool live: gameRow.game.state === "in"
    height: column.implicitHeight + Style.space(6)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(5)
      color: root.foreground
      opacity: rowMouse.containsMouse && gameRow.game.link ? 0.07 : 0
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.right: status.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Repeater {
        model: ["away", "home"]

        Item {
          id: line
          required property string modelData
          readonly property var part: gameRow.game[line.modelData] || ({})
          readonly property bool dim: Scores.dimmed(gameRow.game, line.modelData)
          width: column.width
          height: Math.max(gameRow.logoSize, abbr.implicitHeight)

          Image {
            id: logo
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: gameRow.logoSize
            height: gameRow.logoSize
            source: Scores.logoFor(line.part, root.darkTheme)
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            opacity: line.dim ? 0.5 : 1
          }

          Text {
            id: abbr
            anchors.left: logo.right
            anchors.leftMargin: Style.space(6)
            anchors.right: score.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(line.part.abbr || line.part.name || "")
            color: root.foreground
            opacity: line.dim ? 0.5 : 1
            font.family: root.fontFamily
            font.pixelSize: gameRow.lineSize
            font.weight: line.dim ? Font.Normal : Font.DemiBold
            elide: Text.ElideRight
          }

          Text {
            id: score
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: line.part.score === null || line.part.score === undefined ? "" : String(line.part.score)
            color: gameRow.live ? Color.accent : root.foreground
            opacity: line.dim ? 0.5 : 1
            font.family: root.fontFamily
            font.pixelSize: gameRow.lineSize
            font.weight: line.dim ? Font.Normal : Font.DemiBold
            font.features: { "tnum": 1 }
          }
        }
      }
    }

    Column {
      id: status
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(82)
      spacing: Style.space(1)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: Scores.statusText(gameRow.game, root.nowMs, root.h24)
        color: gameRow.live ? Color.accent : root.foreground
        opacity: gameRow.live ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: gameRow.live ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
      }

      Text {
        visible: text.length > 0
        width: parent.width
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: gameRow.game.state === "pre" ? String(gameRow.game.network || "") : ""
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      enabled: !!gameRow.game.link
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.open(gameRow.game)
    }
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: Scores.title(root.sample, root.settings)
      trailing: Scores.headerNote(root.sample)
      dotColor: Scores.liveCount(root.sample) > 0 ? Color.accent : root.foreground
      dotOpacity: Scores.liveCount(root.sample) > 0 ? 1 : 0.35
      pulse: Scores.liveCount(root.sample) > 0
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    GameRow {
      id: featuredRow
      visible: !!root.featured
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      width: parent.width
      game: root.featured || ({})
      lineSize: Style.font.title
      logoSize: Style.space(22)
    }

    Rectangle {
      id: divider
      visible: featuredRow.visible && root.games.length > 0
      anchors.top: featuredRow.bottom
      anchors.topMargin: Style.space(4)
      width: parent.width
      height: 1
      color: root.foreground
      opacity: 0.12
    }

    ListView {
      id: list
      anchors.top: featuredRow.visible ? divider.bottom : header.bottom
      anchors.topMargin: Style.space(4)
      anchors.bottom: parent.bottom
      width: parent.width
      clip: true
      spacing: Style.space(1)
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.games

      delegate: GameRow {
        required property var modelData
        width: ListView.view.width
        game: modelData
      }
    }

    Text {
      visible: !!root.sample && !root.featured && root.games.length === 0
      anchors.centerIn: list
      width: list.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.sample && !root.sample.ok ? String(root.sample.error || "ESPN did not answer") : "No games scheduled"
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
