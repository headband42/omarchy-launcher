import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit/kit.js" as Kit
import "nfl.js" as Nfl

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

  property string filterText: ""
  property int selectedIndex: 0
  property var rows: []
  property bool catalogLoaded: false
  property bool catalogFailed: false

  readonly property int teamId: {
    var n = Number(root.settings && root.settings.teamId)
    if (!isFinite(n) || n <= 0) return 0
    return Math.round(n)
  }
  readonly property bool teamColors: !!(root.settings && root.settings.teamColors)
  readonly property bool darkPaper: Nfl.isDark(Nfl.colorHex(Color.menu.background))
  // Wide enough for a club name and a logo, not half of the settings overlay.
  readonly property int conferenceColumnWidth: Style.space(132)
  readonly property int contentWidth: root.conferenceColumnWidth * 2 + Style.space(16)

  function filteredSide(side, query) {
    if (!side) return null
    var teams = []
    var all = side.teams || []
    for (var i = 0; i < all.length; i++) {
      if (!query || root.matches(all[i], query)) teams.push(all[i])
    }
    if (!teams.length) return null
    return { id: side.id, name: side.name, teams: teams }
  }

  // Division bands, AFC on the left and NFC on the right, narrowed by the
  // filter the user is typing.
  readonly property var filteredRows: {
    var query = root.filterText.trim().toLowerCase()
    var out = []
    var bands = root.rows || []
    for (var i = 0; i < bands.length; i++) {
      var afc = root.filteredSide(bands[i] && bands[i].afc, query)
      var nfc = root.filteredSide(bands[i] && bands[i].nfc, query)
      if (!afc && !nfc) continue
      out.push({ region: bands[i].region, afc: afc, nfc: nfc })
    }
    return out
  }
  // The same clubs in reading order, for the arrow keys.
  readonly property var visibleTeams: {
    var out = []
    var bands = root.filteredRows
    for (var i = 0; i < bands.length; i++) {
      var afcTeams = (bands[i].afc && bands[i].afc.teams) || []
      var nfcTeams = (bands[i].nfc && bands[i].nfc.teams) || []
      for (var j = 0; j < afcTeams.length; j++) out.push(afcTeams[j])
      for (var k = 0; k < nfcTeams.length; k++) out.push(nfcTeams[k])
    }
    return out
  }

  function logoSource(team) {
    var path = Nfl.logoPath(team, root.darkPaper)
    return path ? Qt.resolvedUrl(path) : ""
  }

  function matches(team, query) {
    var fields = [team.abbr, team.full, team.name, team.nickname, team.divisionName]
    for (var i = 0; i < fields.length; i++) {
      if (String(fields[i] || "").toLowerCase().indexOf(query) >= 0) return true
    }
    return false
  }

  function flatIndex(team) {
    var teams = root.visibleTeams
    for (var i = 0; i < teams.length; i++) {
      if (Number(teams[i].id) === Number(team && team.id)) return i
    }
    return -1
  }

  function choose(id) {
    var n = Number(id)
    if (!isFinite(n) || n <= 0) return
    // Keep the color choice when the club changes. An empty object forgets both.
    var next = { teamId: Math.round(n) }
    if (root.teamColors) next.teamColors = true
    root.settings = next
    root.forceActiveFocus()
  }

  function setTeamColors(on) {
    if (!root.teamId) return
    var next = { teamId: root.teamId }
    if (on) next.teamColors = true
    root.settings = next
  }

  function clearTeam() {
    root.settings = ({})
    root.forceActiveFocus()
  }

  function handleEscape() {
    if (!root.filterText) return false
    root.filterText = ""
    root.selectedIndex = 0
    return true
  }

  function handleKey(event) {
    if (!event) return false
    var listed = root.visibleTeams.length
    if (event.key === Qt.Key_Up && listed > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + listed) % listed
      return true
    }
    if (event.key === Qt.Key_Down && listed > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % listed
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && listed > 0) {
      var picked = root.visibleTeams[root.selectedIndex]
      if (picked) root.choose(picked.id)
      return true
    }
    if (event.key === Qt.Key_Delete && !root.filterText && root.teamId) {
      root.clearTeam()
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      root.filterText = root.filterText.slice(0, -1)
      root.selectedIndex = 0
      return true
    }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
      root.filterText += event.text
      root.selectedIndex = 0
      return true
    }
    return false
  }

  Process {
    id: teamProbe
    command: ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("nfl.py")), "--teams"]
    stdout: StdioCollector { id: teamOut; waitForEnd: true }
    onExited: function(exitCode) {
      var ok = false
      try {
        var parsed = JSON.parse(teamOut.text || "")
        var bands = parsed && parsed.rows && parsed.rows.length ? parsed.rows : []
        ok = exitCode === 0 && bands.length > 0
        if (ok) root.rows = bands
      } catch (e) { ok = false }
      if (!ok) root.rows = []
      root.catalogLoaded = true
      root.catalogFailed = !ok
    }
  }

  implicitWidth: body.implicitWidth
  implicitHeight: body.implicitHeight

  Component.onCompleted: teamProbe.running = true
  onFilterTextChanged: root.selectedIndex = 0

  Column {
    id: body
    spacing: Style.spacing.sm

    Text {
      width: root.contentWidth
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Clubs by division. Empty shows the week's games."
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.62
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    BorderSurface {
      width: root.contentWidth
      height: Style.space(36)
      radius: root.cornerRadius
      color: !root.teamId ? root.hoverFill : "transparent"
      borderSpec: !root.teamId ? root.borderSpec : Border.none()

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Week slate"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: !root.teamId ? Font.DemiBold : Font.Medium
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "every game"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clearTeam()
      }
    }

    Row {
      visible: root.teamId > 0
      spacing: Style.space(8)
      height: Style.space(28)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Team colors"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: root.teamColors
        onToggled: root.setTeamColors(!root.teamColors)
      }
    }

    Text {
      visible: root.catalogFailed
      width: root.contentWidth
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Clubs could not be loaded."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: !root.catalogLoaded && !root.catalogFailed
      width: root.contentWidth
      textFormat: Text.PlainText
      text: "Loading clubs…"
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      visible: root.catalogLoaded && !root.catalogFailed
      spacing: Style.space(8)

      Repeater {
        model: root.filteredRows.length

        Row {
          id: bandRow
          required property int index
          readonly property var band: root.filteredRows[index] || ({})
          spacing: Style.space(16)

          Repeater {
            model: 2

            Item {
              id: conferenceCol
              required property int index
              readonly property var side: index === 0 ? bandRow.band.afc : bandRow.band.nfc
              width: root.conferenceColumnWidth
              height: sideCol.implicitHeight

              Column {
                id: sideCol
                width: parent.width
                visible: conferenceCol.side && conferenceCol.side.teams && conferenceCol.side.teams.length > 0
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: conferenceCol.side ? String(conferenceCol.side.name || "") : ""
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Repeater {
                  model: conferenceCol.side && conferenceCol.side.teams ? conferenceCol.side.teams.length : 0

                  BorderSurface {
                    id: teamRow
                    required property int index
                    readonly property var team: (conferenceCol.side && conferenceCol.side.teams && conferenceCol.side.teams[index]) || ({})
                    readonly property bool chosen: Number(team.id) === root.teamId
                    readonly property bool keyed: root.flatIndex(team) === root.selectedIndex
                    width: sideCol.width
                    height: Style.space(28)
                    radius: Style.space(6)
                    color: teamRow.chosen || teamRow.keyed ? root.hoverFill : "transparent"
                    borderSpec: teamRow.chosen ? root.borderSpec : Border.none()

                    Image {
                      id: logo
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(18)
                      height: Style.space(18)
                      source: root.logoSource(teamRow.team)
                      fillMode: Image.PreserveAspectFit
                      mipmap: true
                      asynchronous: true
                      sourceSize.width: 96
                      sourceSize.height: 96
                    }

                    Text {
                      anchors.left: logo.right
                      anchors.leftMargin: Style.space(6)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: String(teamRow.team.nickname || teamRow.team.full || "")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: teamRow.chosen ? Font.DemiBold : Font.Normal
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.selectedIndex = root.flatIndex(teamRow.team)
                      onClicked: root.choose(teamRow.team.id)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    Text {
      visible: root.catalogLoaded && !root.catalogFailed && root.visibleTeams.length === 0
      width: root.contentWidth
      textFormat: Text.PlainText
      text: "No matches"
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
