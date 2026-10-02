import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "fantasy.js" as Fantasy

// This week's fantasy football matchups. One league fills the tile: both
// teams and their scores, players left to play, the projection, and alerts
// for a starter on a bye, out, or an empty slot. Two or more leagues get a
// row each. A matchup opens that league on its own site; the header and the
// margins launch the slot's Opens.
Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  // A reply from fantasy.py this session, not the cache.
  property bool live: false
  // The last poll got no answer, so the scores are the previous ones.
  property bool offline: false

  // The stocks tile's tones, so a lead reads the same everywhere.
  readonly property color upColor: Qt.rgba(0.22, 0.50, 0.30, 1)
  readonly property color downColor: Qt.rgba(0.62, 0.22, 0.22, 1)

  readonly property var settings: root.tile && root.tile.settings ? root.tile.settings : ({})
  readonly property var stored: Fantasy.leaguesFrom(root.settings)
  readonly property string request: Fantasy.requestArg(root.settings)
  readonly property bool current: !!(root.sample && root.sample.ok === true
    && String(root.sample.request || "") === root.request)
  // Each stored league with its matchup, in the order the settings list them.
  readonly property var rows: {
    var byKey = {}
    var leagues = root.current ? Fantasy.toList(root.sample.leagues) : []
    for (var i = 0; i < leagues.length; i++) byKey[String(leagues[i].key)] = leagues[i]
    return root.stored.map(function(entry) {
      return { stored: entry, league: byKey[Fantasy.entryKey(entry)] || null }
    })
  }
  readonly property bool single: root.rows.length === 1
  readonly property var only: root.single ? root.rows[0].league : null
  readonly property bool anyLive: root.current && !!root.sample.live
  readonly property int urgent: {
    var n = 0
    for (var i = 0; i < root.rows.length; i++) {
      var league = root.rows[i].league
      if (league) n += Fantasy.urgentCount(league.alerts)
    }
    return n
  }
  readonly property string cachePath: {
    var base = String(Quickshell.env("XDG_CACHE_HOME") || "")
    if (!base) base = String(Quickshell.env("HOME") || "") + "/.cache"
    return base + "/ande.launcher/fantasy.json"
  }

  function toneColor(league) {
    var tone = Fantasy.tone(league)
    if (tone === "up") return root.upColor
    if (tone === "down") return root.downColor
    return root.alpha(0.45)
  }

  function alpha(a) {
    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, a)
  }

  function openLeague(league) {
    var url = Fantasy.safeUrl(league && league.url)
    if (url && root.host && typeof root.host.openUrl === "function") root.host.openUrl(url)
    else if (root.host && typeof root.host.launchDefault === "function") root.host.launchDefault()
  }

  function apply(data) {
    if (data && data.ok === true) {
      root.sample = data
      root.live = true
      root.offline = false
      return
    }
    // No answer. Matchups already drawn stay up, marked offline.
    if (root.current) root.offline = true
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("fantasy.py")
    args: root.request ? ["--leagues", root.request] : []
    interval: Math.max(60000, Math.min(1800000, Number(root.sample && root.sample.pollMs) || 300000))
    active: root.visible && root.request.length > 0
    onSampled: function(data) { root.apply(data) }
  }

  // The last good reply, drawn while the first poll is out.
  FileView {
    path: root.cachePath
    printErrors: false
    watchChanges: false
    onLoaded: {
      if (root.live) return
      var cached = Fantasy.fromCache(text(), root.request)
      if (cached) root.sample = cached
    }
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: Fantasy.headerTitle(root.current ? root.sample : null)
      trailing: {
        if (root.offline) return "offline"
        if (root.single) return Fantasy.rowTitle(root.only, root.rows[0].stored)
        if (root.urgent > 0) return root.urgent === 1 ? "1 alert" : root.urgent + " alerts"
        return root.anyLive ? "live" : ""
      }
      dotColor: root.urgent > 0 ? Color.urgent : (root.anyLive && !root.offline ? Color.accent : root.foreground)
      dotOpacity: root.urgent > 0 || (root.anyLive && !root.offline) ? 1 : 0.35
      pulse: root.anyLive && root.live && !root.offline
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // —— Nothing set up ——
    Column {
      visible: root.rows.length === 0
      anchors.centerIn: parent
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Add a league with the gear"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Sleeper · ESPN · Fleaflicker · MFL · Fantrax · Yahoo (beta)"
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    // —— One league: the matchup ——
    Item {
      id: card
      visible: root.single
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      readonly property var league: root.only
      readonly property bool ready: !!(card.league && card.league.ok !== false && card.league.me)
      readonly property bool scored: Fantasy.hasScores(card.league)
      readonly property string tone: Fantasy.tone(card.league)

      Text {
        visible: !card.ready
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: card.league && card.league.ok === false ? String(card.league.error || "Not available")
          : "Loading the matchup…"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Rectangle {
        anchors.fill: matchup
        anchors.margins: -Style.space(4)
        radius: Style.space(6)
        color: root.foreground
        opacity: matchupMouse.containsMouse ? 0.07 : 0
      }

      MouseArea {
        id: matchupMouse
        anchors.fill: matchup
        anchors.margins: -Style.space(4)
        visible: card.ready
        hoverEnabled: true
        cursorShape: Fantasy.safeUrl(card.league && card.league.url) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.openLeague(card.league)
      }

      Column {
        id: matchup
        visible: card.ready
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        Repeater {
          model: card.ready ? (card.league.opp ? ["me", "opp"] : ["me"]) : []

          Column {
            id: team
            required property var modelData
            readonly property var line: card.league[team.modelData] || ({})
            readonly property bool mine: team.modelData === "me"
            readonly property bool leading: (card.tone === "up") === team.mine && card.tone !== "even" && card.tone !== ""
            width: matchup.width
            spacing: 1

            Item {
              width: parent.width
              height: Math.ceil(Math.max(nameText.implicitHeight, scoreText.implicitHeight))

              Text {
                id: nameText
                anchors.left: parent.left
                anchors.right: scoreText.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(team.line.name || (team.mine ? "You" : "Opponent"))
                color: root.foreground
                opacity: team.mine ? 1 : 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: team.mine
                elide: Text.ElideRight
              }

              Text {
                id: scoreText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: card.scored
                textFormat: Text.PlainText
                text: Fantasy.formatScore(team.line.score)
                color: team.leading && Fantasy.started(card.league) ? (team.mine ? root.upColor : root.downColor) : root.foreground
                opacity: team.leading || card.tone === "" || card.tone === "even" ? 1 : 0.6
                font.family: root.fontFamily
                font.pixelSize: team.mine ? Style.font.display : Style.font.heading
                font.bold: team.mine
                font.features: ({ "tnum": 1 })
              }
            }

            Text {
              width: parent.width
              visible: text.length > 0
              textFormat: Text.PlainText
              text: Fantasy.sideLine(team.line, true) || String(team.line.record || "")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.features: ({ "tnum": 1 })
              elide: Text.ElideRight
            }
          }
        }

        Text {
          width: parent.width
          visible: card.ready && text.length > 0
          textFormat: Text.PlainText
          text: card.ready ? String(card.league.note || "") : ""
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }

      Text {
        id: alertText
        visible: card.ready && text.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(4)
        textFormat: Text.PlainText
        text: card.ready ? Fantasy.alertsLine(card.league.alerts, 4) : ""
        color: Fantasy.urgentCount(card.ready ? card.league.alerts : []) > 0 ? Color.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        id: footer
        visible: card.ready
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: card.ready ? Fantasy.footerLine(card.league) : ""
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // —— Two or more leagues: a row each ——
    ListView {
      id: list
      visible: root.rows.length > 1
      anchors.top: header.bottom
      anchors.topMargin: Style.space(4)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: -Style.space(4)
      anchors.rightMargin: -Style.space(4)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows.length > 1 ? root.rows : []
      // Scroll only when the rows overflow, so the wheel still reaches the launcher.
      interactive: contentHeight > height + 1

      readonly property int minRow: Math.ceil(titleMetric.height + detailMetric.height + Style.space(10))
      readonly property int rowHeight: Math.max(list.minRow,
        Math.min(Math.round(list.minRow * 1.5), Math.floor(list.height / Math.max(1, root.rows.length))))

      delegate: Item {
        id: row
        required property var modelData
        readonly property var league: row.modelData.league
        readonly property var stored: row.modelData.stored
        readonly property bool failed: !!(row.league && row.league.ok === false)
        readonly property bool alerting: !!row.league && Fantasy.urgentCount(row.league.alerts) > 0
        width: ListView.view.width
        height: list.rowHeight

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: root.foreground
          opacity: rowMouse.containsMouse ? 0.07 : 0
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Fantasy.safeUrl(row.league && row.league.url) ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.openLeague(row.league)
        }

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Item {
            width: parent.width
            height: Math.ceil(titleMetric.height)

            Text {
              anchors.left: parent.left
              anchors.right: pair.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Fantasy.rowTitle(row.league, row.stored)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Row {
              id: pair
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                readonly property string tone: Fantasy.tone(row.league)
                visible: tone === "up" || tone === "down"
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: tone === "up" ? "▲" : "▼"
                color: root.toneColor(row.league)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: row.league ? Fantasy.scorePair(row.league) : ""
                color: root.foreground
                opacity: row.league && !Fantasy.started(row.league) ? 0.6 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.features: ({ "tnum": 1 })
              }
            }
          }

          Item {
            width: parent.width
            height: Math.ceil(detailMetric.height)

            Text {
              anchors.left: parent.left
              anchors.right: record.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: row.league ? Fantasy.rowDetail(row.league) : "Loading…"
              color: row.alerting || row.failed ? Color.urgent : root.foreground
              opacity: row.alerting || row.failed ? 1 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              id: record
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: row.league && row.league.me ? String(row.league.me.record || "") : ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.features: ({ "tnum": 1 })
            }
          }
        }
      }
    }
  }

  TextMetrics {
    id: titleMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    text: "Ag"
  }

  TextMetrics {
    id: detailMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Ag"
  }
}
