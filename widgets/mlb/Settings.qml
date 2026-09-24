import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

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
  property var divisions: []
  property bool catalogLoaded: false
  property bool catalogFailed: false

  readonly property int teamId: {
    var n = Number(root.settings && root.settings.teamId)
    if (!isFinite(n) || n <= 0) return 0
    return Math.round(n)
  }
  readonly property var filteredDivisions: {
    var query = root.filterText.trim().toLowerCase()
    var out = []
    var groups = root.divisions || []
    for (var i = 0; i < groups.length; i++) {
      var teams = []
      var all = (groups[i] && groups[i].teams) || []
      for (var j = 0; j < all.length; j++) {
        if (!query || root.matches(all[j], query)) teams.push(all[j])
      }
      if (teams.length) out.push({ id: groups[i].id, name: groups[i].name, teams: teams })
    }
    return out
  }
  readonly property var visibleTeams: {
    var out = []
    var groups = root.filteredDivisions
    for (var i = 0; i < groups.length; i++) {
      var teams = groups[i].teams || []
      for (var j = 0; j < teams.length; j++) out.push(teams[j])
    }
    return out
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function logoSource(id) {
    var n = Number(id)
    if (!isFinite(n) || n <= 0) return ""
    return Qt.resolvedUrl("logos/" + Math.round(n) + ".png")
  }

  function matches(team, query) {
    var name = String(team.name || "").toLowerCase()
    var location = String(team.location || "").toLowerCase()
    var club = String(team.club || "").toLowerCase()
    var abbr = String(team.abbr || "").toLowerCase()
    return name.indexOf(query) >= 0 || location.indexOf(query) >= 0 || club.indexOf(query) >= 0 || abbr.indexOf(query) >= 0
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
    // The settings host stores this for the widget. An empty object forgets it.
    root.settings = { teamId: Math.round(n) }
    root.forceActiveFocus()
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
    command: ["/usr/bin/python3", root.scriptPath("sample.py"), "--teams"]
    stdout: StdioCollector { id: teamOut; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = null
      var ok = false
      try {
        parsed = JSON.parse(teamOut.text || "")
        ok = exitCode === 0 && parsed && Array.isArray(parsed.divisions)
      } catch (e) { ok = false }
      root.divisions = ok ? parsed.divisions : []
      root.catalogLoaded = true
      root.catalogFailed = !ok
    }
  }

  Component.onCompleted: teamProbe.running = true
  onFilterTextChanged: root.selectedIndex = 0

  Item {
    anchors.fill: parent

    Text {
      id: filterLabel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Clubs by division. Empty follows every live game."
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.62
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    BorderSurface {
      id: liveChip
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: filterLabel.bottom
      anchors.topMargin: Style.spacing.sm
      height: Style.space(36)
      radius: root.cornerRadius
      color: !root.teamId ? root.hoverFill : "transparent"
      borderSpec: !root.teamId ? root.borderSpec : Border.none()

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Live games"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: !root.teamId ? Font.DemiBold : Font.Medium
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clearTeam()
      }
    }

    Text {
      visible: root.catalogFailed
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: liveChip.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: "Clubs could not be loaded."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: !root.catalogLoaded && !root.catalogFailed
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: liveChip.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: "Loading clubs…"
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Flickable {
      id: gridFlick
      visible: root.catalogLoaded && !root.catalogFailed
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: liveChip.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      contentWidth: width
      contentHeight: divisionGrid.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick

      Grid {
        id: divisionGrid
        width: gridFlick.width
        columns: 2
        columnSpacing: Style.space(10)
        rowSpacing: Style.space(10)

        Repeater {
          model: root.filteredDivisions.length

          Column {
            id: divisionCol
            required property int index
            readonly property var group: root.filteredDivisions[index] || ({})
            width: Math.floor((divisionGrid.width - divisionGrid.columnSpacing) / 2)
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(divisionCol.group.name || "")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              elide: Text.ElideRight
            }

            Repeater {
              model: (divisionCol.group.teams || []).length

              BorderSurface {
                id: teamRow
                required property int index
                readonly property var team: (divisionCol.group.teams || [])[index] || ({})
                readonly property bool chosen: Number(team.id) === root.teamId
                readonly property bool keyed: root.flatIndex(team) === root.selectedIndex
                width: divisionCol.width
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
                  source: root.logoSource(teamRow.team.id)
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  sourceSize.width: width
                  sourceSize.height: height
                }

                Text {
                  anchors.left: logo.right
                  anchors.leftMargin: Style.space(4)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(teamRow.team.club || teamRow.team.name || "")
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

    Text {
      visible: root.catalogLoaded && !root.catalogFailed && root.visibleTeams.length === 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: liveChip.bottom
      anchors.topMargin: Style.spacing.lg
      textFormat: Text.PlainText
      text: "No matches"
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
