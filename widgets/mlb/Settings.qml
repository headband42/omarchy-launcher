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

  property string mode: "home"
  property string filterText: ""
  property int selectedIndex: 0
  property var catalog: []
  property bool catalogLoaded: false
  property bool catalogFailed: false

  readonly property string panelTitle: root.mode === "pick" ? "Choose a club" : ""
  readonly property int teamId: {
    var n = Number(root.settings && root.settings.teamId)
    if (!isFinite(n) || n <= 0) return 0
    return Math.round(n)
  }
  readonly property var selected: {
    var id = root.teamId
    if (!id) return null
    for (var i = 0; i < root.catalog.length; i++) {
      if (Number(root.catalog[i].id) === id) return root.catalog[i]
    }
    return { id: id, name: "Team " + id, abbr: "", location: "", club: "" }
  }
  readonly property var filtered: {
    var query = root.filterText.trim().toLowerCase()
    var out = []
    var all = root.catalog
    for (var i = 0; i < all.length; i++) {
      var team = all[i]
      if (query && !root.matches(team, query)) continue
      out.push(team)
    }
    return out
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function matches(team, query) {
    var name = String(team.name || "").toLowerCase()
    var location = String(team.location || "").toLowerCase()
    var club = String(team.club || "").toLowerCase()
    var abbr = String(team.abbr || "").toLowerCase()
    return name.indexOf(query) >= 0 || location.indexOf(query) >= 0 || club.indexOf(query) >= 0 || abbr.indexOf(query) >= 0
  }

  function teamCaption(team) {
    if (!team) return ""
    var bits = []
    if (team.abbr) bits.push(String(team.abbr))
    if (team.location) bits.push(String(team.location))
    return bits.join(" · ")
  }

  function choose(id) {
    var n = Number(id)
    if (!isFinite(n) || n <= 0) return
    // The settings host stores this for the widget. An empty object forgets it.
    root.settings = { teamId: Math.round(n) }
    root.filterText = ""
    root.mode = "home"
    root.forceActiveFocus()
  }

  function clearTeam() {
    root.settings = ({})
    root.forceActiveFocus()
  }

  function openPick() {
    root.mode = "pick"
    root.filterText = ""
    root.selectedIndex = 0
    root.forceActiveFocus()
  }

  function handleEscape() {
    if (root.mode !== "pick") return false
    if (root.filterText) {
      root.filterText = ""
      root.selectedIndex = 0
      return true
    }
    root.mode = "home"
    return true
  }

  function handleKey(event) {
    if (!event) return false
    if (root.mode !== "pick") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.openPick()
        return true
      }
      if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.teamId) {
        root.clearTeam()
        return true
      }
      return false
    }
    var listed = root.filtered.length
    if (event.key === Qt.Key_Up && listed > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + listed) % listed
      return true
    }
    if (event.key === Qt.Key_Down && listed > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % listed
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && listed > 0) {
      var picked = root.filtered[root.selectedIndex]
      if (picked) root.choose(picked.id)
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
      var rows = []
      var ok = false
      try {
        rows = JSON.parse(teamOut.text || "[]")
        ok = exitCode === 0 && Array.isArray(rows)
      } catch (e) { ok = false }
      root.catalog = ok ? rows : []
      root.catalogLoaded = true
      root.catalogFailed = !ok
    }
  }

  Component.onCompleted: teamProbe.running = true
  onFilterTextChanged: root.selectedIndex = 0

  Column {
    visible: root.mode === "home"
    anchors.fill: parent
    spacing: Style.spacing.md

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Choose a favorite club and the tile follows it. A live game shows the box score, the count, the bases, and who is batting and pitching. Between games it shows the last box score and when the next game starts. Leave this empty to show every live game. During the playoffs, a club that did not qualify shows every live game too."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    BorderSurface {
      width: parent.width
      height: Style.space(58)
      radius: root.cornerRadius
      color: homeMouse.containsMouse || root.activeFocus ? root.hoverFill : "transparent"
      borderSpec: homeMouse.containsMouse || root.activeFocus ? root.borderSpec : Border.none()

      Column {
        anchors.left: parent.left
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.selected ? String(root.selected.name || "") : "Choose a club"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.selected ? (root.teamCaption(root.selected) || "Favorite club") : "Live games"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Item {
        id: clearButton
        visible: root.teamId > 0
        width: Style.space(40)
        height: parent.height
        anchors.right: parent.right
        z: 2

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: ""
          color: root.foreground
          opacity: clearMouse.containsMouse ? 1 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clearTeam()
        }
      }

      MouseArea {
        id: homeMouse
        anchors.left: parent.left
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openPick()
      }
    }
  }

  Item {
    visible: root.mode === "pick"
    anchors.fill: parent

    Text {
      id: searchText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Search clubs…"
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    Text {
      visible: root.catalogFailed
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
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
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: "Loading clubs…"
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    ListView {
      id: pickList
      visible: root.catalogLoaded && !root.catalogFailed
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.filtered.length
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (count > 0 && currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: BorderSurface {
        required property int index
        readonly property var team: root.filtered[index] || {}
        width: ListView.view.width
        height: Style.space(50)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(team.name || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.teamCaption(team)
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.choose(team.id)
        }
      }
    }

    Text {
      visible: root.catalogLoaded && !root.catalogFailed && root.filtered.length === 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
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
