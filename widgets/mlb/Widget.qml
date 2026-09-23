import QtQuick
import Quickshell.Io
import qs.Commons

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
  readonly property string mode: String((root.sample && root.sample.mode) || "")
  readonly property bool failed: root.loaded && !!root.sample && root.sample.ok === false
  readonly property var shown: root.sample && root.sample.focus ? root.sample.focus : null
  readonly property var games: {
    var rows = root.sample && root.sample.games
    return rows && rows.length ? rows : []
  }
  readonly property var nextGame: root.sample && root.sample.next ? root.sample.next : null
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
  readonly property bool showLine: !!(root.shown && root.shown.hasLine && root.cellW >= (root.wideInnings ? Style.space(16) : Style.space(11)))
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

  function openGameday(url) {
    var value = String(url || "")
    if (value && root.host && root.host.openUrl) root.host.openUrl(value)
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

  Component.onCompleted: root.refresh()
  onVisibleChanged: if (visible) root.refresh()
  onTeamIdChanged: {
    root.sample = ({})
    root.haveScore = false
    root.loaded = false
    if (root.visible) root.refresh()
  }

  // The tile's own click launches Opens. This one opens the game on Gameday.
  MouseArea {
    z: 0
    anchors.fill: parent
    enabled: root.tileUrl.length > 0
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.openGameday(root.tileUrl)
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(10)

    MouseArea {
      z: 0
      anchors.fill: parent
      enabled: root.mode === "board"
      onClicked: {}
    }

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
        color: root.foreground
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
        color: root.foreground
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
        color: root.foreground
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
        color: root.foreground
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
        color: root.foreground
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
        color: root.foreground
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
          color: Color.urgent
        }

        Text {
          anchors.left: boardDot.right
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String((root.sample && root.sample.banner) || "Live") + (root.games.length ? " · " + root.games.length : "")
          color: root.foreground
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
              color: rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
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
                  color: root.foreground
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
                  color: root.foreground
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
                  color: root.foreground
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
                color: root.foreground
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
              onClicked: root.openGameday(game.gameday)
            }
          }
        }
      }
    }

    Column {
      id: score
      z: 1
      visible: root.mode === "live" || root.mode === "final"
      width: parent.width
      spacing: Style.space(2)
      y: Math.max(0, Math.round((parent.height - height) / 2))

      Item {
        width: parent.width
        height: root.shown && root.shown.live ? Style.space(24) : Style.font.body + Style.space(2)

        Rectangle {
          id: liveDot
          visible: root.shown && root.shown.live
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: Color.urgent
        }

        Text {
          anchors.left: liveDot.visible ? liveDot.right : parent.left
          anchors.leftMargin: liveDot.visible ? Style.space(6) : 0
          anchors.right: diamond.visible ? diamond.left : parent.right
          anchors.rightMargin: diamond.visible ? Style.space(4) : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: {
            var banner = String((root.sample && root.sample.banner) || "")
            var status = String((root.shown && root.shown.status) || "")
            if (banner && status) return banner + " · " + status
            return banner || status
          }
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        Item {
          id: diamond
          visible: !!(root.shown && root.shown.live)
          width: Style.space(26)
          height: Style.space(20)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          property var bases: (root.shown && root.shown.bases) || []

          Rectangle {
            width: Style.space(7)
            height: Style.space(7)
            radius: 1
            rotation: 45
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            color: diamond.bases[1] ? root.foreground : "transparent"
            border.color: root.foreground
            border.width: 1
          }

          Rectangle {
            width: Style.space(7)
            height: Style.space(7)
            radius: 1
            rotation: 45
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            color: diamond.bases[2] ? root.foreground : "transparent"
            border.color: root.foreground
            border.width: 1
          }

          Rectangle {
            width: Style.space(7)
            height: Style.space(7)
            radius: 1
            rotation: 45
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: diamond.bases[0] ? root.foreground : "transparent"
            border.color: root.foreground
            border.width: 1
          }
        }
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
              color: root.foreground
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
                color: root.foreground
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
                color: root.foreground
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
                color: root.foreground
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
                color: root.foreground
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

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.away && root.shown.away.abbr) || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.sideStrong("away") ? Font.DemiBold : Font.Medium
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.away && root.shown.away.score) || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
          }
        }

        Item {
          width: parent.width
          height: Style.font.heading + Style.space(2)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.home && root.shown.home.abbr) || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.sideStrong("home") ? Font.DemiBold : Font.Medium
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String((root.shown && root.shown.home && root.shown.home.score) || "")
            color: root.foreground
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
          color: root.foreground
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
        color: root.foreground
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
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        visible: !!(root.shown && root.shown.pitcherLine)
        width: parent.width
        textFormat: Text.PlainText
        text: root.shown ? String(root.shown.pitcherLine || "") : ""
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Item {
        id: nextBlock
        visible: root.mode === "final" && root.nextGame
        width: parent.width
        height: visible ? nextCol.implicitHeight : 0

        Column {
          id: nextCol
          width: parent.width
          spacing: 0

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.nextGame ? (String(root.nextGame.kicker || "Next") + "  " + String(root.nextGame.when || "")) : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.nextGame ? String(root.nextGame.where || "") : ""
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: nextBlock.visible && root.nextGame && String(root.nextGame.gameday || "").length > 0
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.openGameday(root.nextGame.gameday)
        }
      }
    }
  }
}
