import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/kit.js" as Kit
import "scores.js" as Scores

// One league, and optionally a team whose game the tile puts on top.
Item {
  id: root
  focus: true

  property var tile: ({})
  property var settings: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color hoverFill: Color.menu.background
  property var borderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius

  property var leagues: []
  property string defaultLeague: "nba"
  property var teams: []
  property string loadedLeague: ""
  property bool teamsFailed: false
  property int selectedIndex: -1

  readonly property string league: Scores.leagueOf(root.settings, root.defaultLeague)
  readonly property string team: Scores.teamOf(root.settings)
  readonly property var matches: Scores.filterTeams(root.teams, searchField.text)
  readonly property string script: Kit.localPath(Qt.resolvedUrl("scores.py"))

  implicitWidth: Style.space(440)
  implicitHeight: Style.space(470)

  function pickLeague(id) {
    if (id === root.league) return
    root.settings = Scores.settingsFor(id, "")
    searchField.text = ""
    root.loadTeams()
  }

  function pickTeam(id) {
    root.settings = Scores.settingsFor(root.league, id === root.team ? "" : id)
    root.forceActiveFocus()
  }

  function loadTeams() {
    if (teamLoader.running) return
    root.teams = []
    root.teamsFailed = false
    teamLoader.command = ["/usr/bin/python3", root.script, "--teams", root.league]
    teamLoader.running = true
  }

  function teamName(id) {
    for (var i = 0; i < root.teams.length; i++) if (root.teams[i].id === id) return root.teams[i].name
    return id
  }

  function handleEscape() {
    if (searchField.activeFocus) {
      root.forceActiveFocus()
      return true
    }
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.matches.length
    if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && count > 0) {
      var step = event.key === Qt.Key_Down ? 1 : -1
      root.selectedIndex = root.selectedIndex < 0 ? 0 : (root.selectedIndex + step + count) % count
      teamList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selectedIndex >= 0 && root.selectedIndex < count) {
      root.pickTeam(root.matches[root.selectedIndex].id)
      return true
    }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) > 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
      searchField.forceActiveFocus()
      searchField.text += event.text
      return true
    }
    return false
  }

  Component.onCompleted: root.forceActiveFocus()

  Poller {
    script: Qt.resolvedUrl("scores.py")
    args: ["--leagues"]
    interval: 0
    onSampled: function(data) {
      if (!data || data.ok !== true) return
      root.leagues = data.leagues || []
      root.defaultLeague = String(data["default"] || "nba")
      if (root.loadedLeague !== root.league) root.loadTeams()
    }
  }

  Process {
    id: teamLoader
    stdout: StdioCollector { id: teamOut; waitForEnd: true }
    onExited: {
      var data = null
      try { data = JSON.parse(teamOut.text || "") } catch (e) { data = null }
      root.teamsFailed = !data || data.ok !== true
      root.teams = data && Array.isArray(data.teams) ? data.teams : []
      root.loadedLeague = root.league
      root.selectedIndex = -1
    }
  }

  Column {
    id: top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(8)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "League"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.leagues

        BorderSurface {
          id: pill
          required property var modelData
          readonly property bool on: modelData.id === root.league
          width: pillText.implicitWidth + Style.space(20)
          height: Style.space(28)
          radius: height / 2
          color: pill.on ? Util.alpha(Color.accent, 0.28) : (pillMouse.containsMouse ? root.hoverFill : Util.alpha(root.foreground, 0.06))

          Text {
            id: pillText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(pill.modelData.name)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.weight: pill.on ? Font.DemiBold : Font.Normal
          }

          MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pickLeague(pill.modelData.id)
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.team ? "Your team: " + root.teamName(root.team) + " · click it again for the whole league"
        : "Your team (optional): its game goes on top"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    TextField {
      id: searchField
      width: parent.width
      placeholderText: root.teamsFailed ? "ESPN did not answer" : "Search teams"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: root.selectedIndex = -1
      onAccepted: if (root.matches.length > 0) root.pickTeam(root.matches[Math.max(0, root.selectedIndex)].id)
    }
  }

  ListView {
    id: teamList
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.topMargin: Style.space(6)
    anchors.bottom: parent.bottom
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds
    model: root.matches

    delegate: BorderSurface {
      id: teamRow
      required property var modelData
      required property int index
      readonly property bool on: modelData.id === root.team
      width: ListView.view.width
      height: Style.space(34)
      radius: root.cornerRadius
      color: teamRow.index === root.selectedIndex || teamMouse.containsMouse ? root.hoverFill : "transparent"
      borderSpec: teamRow.index === root.selectedIndex ? root.borderSpec : Border.none()

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.right: check.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(teamRow.modelData.name) + "  " + String(teamRow.modelData.abbr)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: teamRow.on ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
      }

      Text {
        id: check
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰄬"
        color: Color.accent
        opacity: teamRow.on ? 1 : 0
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: teamMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pickTeam(teamRow.modelData.id)
      }
    }
  }
}
