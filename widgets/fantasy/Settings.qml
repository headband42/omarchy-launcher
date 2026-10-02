import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/kit.js" as Kit
import "fantasy.js" as Fantasy

// The leagues the tile follows, up to six, on any mix of platforms. A league
// is added by platform: a link or ID for most, a username for Sleeper, a
// sign-in for Yahoo (beta). A private ESPN or MFL league takes a cookie or an
// API key (beta). fantasy.py keeps those in its own file, mode 0600; they
// reach it through the environment and never land in these settings.
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

  // home, platform, form, pick
  property string mode: "home"
  property string platformId: ""
  property int selectedIndex: 0
  property string status: ""
  property bool statusBad: false
  property var found: []
  // A team named by the pasted link, picked for the user when it is there.
  property string linkTeam: ""

  readonly property var leagues: Fantasy.leaguesFrom(root.settings)
  readonly property bool full: root.leagues.length >= Fantasy.MAX_LEAGUES
  readonly property var chosen: Fantasy.platform(root.platformId) || ({})
  readonly property bool yahoo: root.platformId === "yahoo"
  readonly property bool busy: finder.running
  readonly property string panelTitle: {
    if (root.mode === "platform") return "Add a league"
    if (root.mode === "form") return String(root.chosen.name || "") + (root.chosen.beta ? " · beta" : "")
    if (root.mode === "pick") return root.teamPick ? "Which team is yours?" : "Pick leagues"
    return ""
  }
  // One league found and no team known yet: the user picks a team. Else the
  // finds already know the user's team (a Sleeper username, a Yahoo sign-in).
  readonly property bool teamPick: root.found.length === 1 && !root.found[0].team
  readonly property var pickRows: {
    if (root.teamPick) {
      var league = root.found[0]
      return Fantasy.toList(league.teams).map(function(team) { return { league: league, team: team } })
    }
    return Fantasy.toList(root.found).map(function(league) { return { league: league, team: null } })
  }
  readonly property int homeCount: root.leagues.length + (root.full ? 0 : 1)
  readonly property int contentWidth: Style.space(400)

  implicitWidth: root.contentWidth
  implicitHeight: {
    if (root.mode === "platform") return platformList.implicitHeight
    if (root.mode === "form") return form.implicitHeight
    if (root.mode === "pick") return Style.space(420)
    return home.implicitHeight
  }

  function entryFor(row) {
    var league = row.league || {}
    var team = row.team
    var entry = {
      p: league.p,
      id: league.id,
      team: team ? team.id : league.team,
      name: league.name,
      teamName: team ? team.name : league.teamName
    }
    var user = team ? team.user : league.user
    if (user) entry.user = user
    if (root.usedSecret || league.p === "yahoo") entry.auth = true
    return entry
  }

  function isAdded(row) {
    var league = row.league || {}
    var team = row.team ? row.team.id : league.team
    for (var i = 0; i < root.leagues.length; i++) {
      var entry = root.leagues[i]
      if (entry.p === league.p && entry.id === league.id && entry.team === String(team)) return true
    }
    return false
  }

  function pick(row) {
    if (!row) return
    if (!root.teamPick && root.isAdded(row)) {
      var index = -1
      for (var i = 0; i < root.leagues.length; i++) {
        if (root.leagues[i].p === row.league.p && root.leagues[i].id === row.league.id) index = i
      }
      if (index >= 0) root.removeAt(index)
      return
    }
    if (root.full && !Fantasy.hasLeague(root.settings, row.league.p, row.league.id)) {
      root.status = "Six leagues is the most the tile shows. Remove one first."
      root.statusBad = true
      return
    }
    root.settings = Fantasy.addLeague(root.settings, root.entryFor(row))
    if (root.teamPick) root.goHome()
  }

  function removeAt(index) {
    if (index < 0 || index >= root.leagues.length) return
    var key = Fantasy.forgetKey(root.settings, index)
    root.settings = Fantasy.removeLeague(root.settings, index)
    if (key) {
      forgetter.command = ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("fantasy.py")), "--forget", key]
      forgetter.running = true
    }
    if (root.mode === "home" && root.selectedIndex >= root.homeCount) root.selectedIndex = Math.max(0, root.homeCount - 1)
  }

  function goHome() {
    root.mode = "home"
    root.status = ""
    root.found = []
    root.clearFields()
    root.selectedIndex = Math.min(root.leagues.length, Math.max(0, root.homeCount - 1))
    root.forceActiveFocus()
  }

  function openPlatforms() {
    if (root.full) return
    root.mode = "platform"
    root.status = ""
    root.selectedIndex = 0
    root.forceActiveFocus()
  }

  function openForm(id) {
    root.platformId = id
    root.mode = "form"
    root.status = ""
    root.statusBad = false
    root.clearFields()
    Qt.callLater(function() {
      if (root.yahoo) clientField.forceActiveFocus()
      else inputField.forceActiveFocus()
    })
  }

  // Secrets leave the fields once fantasy.py has them.
  function clearFields() {
    inputField.text = ""
    s2Field.text = ""
    swidField.text = ""
    keyField.text = ""
    secretField.text = ""
    codeField.text = ""
  }

  property bool usedSecret: false

  function find() {
    if (root.busy) return
    if (root.yahoo) {
      root.start(["--yahoo-signin"], {
        client_id: clientField.text.trim(),
        client_secret: secretField.text.trim(),
        code: codeField.text.trim()
      })
      return
    }
    var parsed = Fantasy.parseLeagueInput(root.platformId, inputField.text)
    if (!parsed) {
      root.status = root.platformId === "sleeper" ? "Type a Sleeper username, or paste a league link."
        : "That isn't a " + root.chosen.name + " league link or ID."
      root.statusBad = true
      return
    }
    var spec = { p: root.platformId }
    for (var key in parsed) {
      if (key !== "team") spec[key] = parsed[key]
    }
    root.linkTeam = parsed.team ? String(parsed.team) : ""
    var secret = {}
    if (root.platformId === "espn" && (s2Field.text.trim() || swidField.text.trim()))
      secret = { espn_s2: s2Field.text.trim(), swid: swidField.text.trim() }
    if (root.platformId === "mfl" && keyField.text.trim())
      secret = { apikey: keyField.text.trim() }
    root.start(["--find", JSON.stringify(spec)], secret)
  }

  function start(args, secret) {
    var hasSecret = Object.keys(secret).length > 0
    root.usedSecret = hasSecret && !root.yahoo
    finder.command = ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("fantasy.py"))].concat(args)
    finder.environment = { ANDE_FANTASY_AUTH: hasSecret ? JSON.stringify(secret) : "" }
    root.status = root.yahoo ? "Signing in…" : "Looking it up…"
    root.statusBad = false
    finder.running = true
  }

  function took(result) {
    var leagues = Fantasy.toList(result && result.leagues)
    if (!result || result.ok !== true || leagues.length === 0) {
      root.status = String((result && result.error) || "That lookup failed.")
      root.statusBad = true
      return
    }
    root.status = ""
    if (leagues.length === 1 && !leagues[0].team && root.linkTeam) {
      var teams = Fantasy.toList(leagues[0].teams)
      for (var i = 0; i < teams.length; i++) {
        if (String(teams[i].id) === root.linkTeam) {
          root.found = leagues
          root.pick({ league: leagues[0], team: teams[i] })
          return
        }
      }
    }
    root.found = leagues
    root.mode = "pick"
    root.selectedIndex = 0
    root.forceActiveFocus()
  }

  function openLink(url) {
    if (!url) return
    opener.command = ["omarchy-launch-browser", url]
    opener.running = true
  }

  function handleEscape() {
    if (root.mode === "pick") {
      root.mode = "form"
      root.status = ""
      Qt.callLater(function() {
        if (root.yahoo) codeField.forceActiveFocus()
        else inputField.forceActiveFocus()
      })
      return true
    }
    if (root.mode === "form") {
      root.mode = "platform"
      root.status = ""
      root.clearFields()
      var ids = Fantasy.PLATFORMS.map(function(p) { return p.id })
      root.selectedIndex = Math.max(0, ids.indexOf(root.platformId))
      root.forceActiveFocus()
      return true
    }
    if (root.mode === "platform") {
      root.goHome()
      return true
    }
    return false
  }

  function step(count, by) {
    if (count <= 0) return
    root.selectedIndex = (root.selectedIndex + by + count) % count
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Escape) return root.handleEscape()
    var up = event.key === Qt.Key_Up
    var down = event.key === Qt.Key_Down
    var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
    if (root.mode === "home") {
      if (up || down) { root.step(root.homeCount, up ? -1 : 1); return true }
      if (enter) {
        if (root.selectedIndex >= root.leagues.length) root.openPlatforms()
        return true
      }
      if (event.key === Qt.Key_Delete) { root.removeAt(root.selectedIndex); return true }
      return false
    }
    if (root.mode === "platform") {
      if (up || down) { root.step(Fantasy.PLATFORMS.length, up ? -1 : 1); return true }
      if (enter) { root.openForm(Fantasy.PLATFORMS[root.selectedIndex].id); return true }
      return false
    }
    if (root.mode === "pick") {
      if (up || down) { root.step(root.pickRows.length, up ? -1 : 1); return true }
      if (enter) { root.pick(root.pickRows[root.selectedIndex]); return true }
      return false
    }
    if (root.mode === "form" && enter) {
      root.find()
      return true
    }
    return false
  }

  Process {
    id: finder
    stdout: StdioCollector { id: findOut; waitForEnd: true }
    onExited: {
      var parsed = null
      try { parsed = JSON.parse(findOut.text || "") } catch (e) { parsed = null }
      if (parsed && parsed.ok) {
        // Saved by fantasy.py; nothing to keep here.
        s2Field.text = ""
        swidField.text = ""
        keyField.text = ""
        secretField.text = ""
        codeField.text = ""
      }
      root.took(parsed)
    }
  }

  Process { id: forgetter }
  Process { id: opener }

  Component.onCompleted: root.forceActiveFocus()

  // —— Home: the leagues, then "Add a league" ——
  Column {
    id: home
    visible: root.mode === "home"
    width: root.contentWidth
    spacing: Style.spacing.md

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.leagues.length === 0
        ? "Follow up to six leagues, on any mix of platforms. The tile shows this week's matchup in each, and warns about a starter who is out, on a bye, or missing."
        : "Up to six, top first. A league on the tile opens on its own site. Delete removes the selected one."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.leagues

        BorderSurface {
          id: leagueRow
          required property int index
          required property var modelData
          readonly property bool beta: !!leagueRow.modelData.auth
          width: parent.width
          height: Style.space(50)
          radius: root.cornerRadius
          color: leagueRow.index === root.selectedIndex ? root.hoverFill : "transparent"
          borderSpec: leagueRow.index === root.selectedIndex ? root.borderSpec : Border.none()

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.selectedIndex = leagueRow.index
            onClicked: root.selectedIndex = leagueRow.index
          }

          Column {
            anchors.left: parent.left
            anchors.right: betaPill.visible ? betaPill.left : removeButton.left
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(leagueRow.modelData.name || Fantasy.platformName(leagueRow.modelData.p))
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: [Fantasy.platformName(leagueRow.modelData.p), String(leagueRow.modelData.teamName || "")]
                .filter(function(part) { return part.length > 0 }).join(" · ")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Rectangle {
            id: betaPill
            visible: leagueRow.beta
            anchors.right: removeButton.left
            anchors.verticalCenter: parent.verticalCenter
            radius: height / 2
            color: Util.alpha(Color.accent, 0.24)
            implicitWidth: betaText.implicitWidth + Style.space(14)
            implicitHeight: betaText.implicitHeight + Style.space(4)

            Text {
              id: betaText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "beta"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            id: removeButton
            width: Style.space(40)
            height: parent.height
            anchors.right: parent.right

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: ""
              color: root.foreground
              opacity: removeMouse.containsMouse ? 1 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: removeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.removeAt(leagueRow.index)
            }
          }
        }
      }

      BorderSurface {
        visible: !root.full
        width: parent.width
        height: Style.space(50)
        radius: root.cornerRadius
        color: root.selectedIndex === root.leagues.length ? root.hoverFill : "transparent"
        borderSpec: root.selectedIndex === root.leagues.length ? root.borderSpec : Border.none()

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
            text: "Add a league"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.leagues.length + " of " + Fantasy.MAX_LEAGUES + " · Sleeper, ESPN, Fleaflicker, MFL, Fantrax, Yahoo"
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
          onEntered: root.selectedIndex = root.leagues.length
          onClicked: root.openPlatforms()
        }
      }
    }

    Text {
      visible: root.full
      width: parent.width
      textFormat: Text.PlainText
      text: Fantasy.MAX_LEAGUES + " of " + Fantasy.MAX_LEAGUES + ". Remove one to add another."
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // —— Which platform ——
  Column {
    id: platformList
    visible: root.mode === "platform"
    width: root.contentWidth
    spacing: Style.spacing.xs

    Repeater {
      model: Fantasy.PLATFORMS

      OptionRow {
        required property int index
        required property var modelData
        width: parent.width
        selected: root.selectedIndex === index
        title: modelData.name
        note: modelData.note
        tag: modelData.beta ? "beta" : ""
        lit: modelData.beta
        hoverFill: root.hoverFill
        selectedBorder: root.borderSpec
        cornerRadius: root.cornerRadius
        fontFamily: root.fontFamily
        foreground: root.foreground
        onHovered: root.selectedIndex = index
        onPicked: root.openForm(modelData.id)
      }
    }
  }

  // —— The league, and a sign-in for the platforms that need one ——
  Column {
    id: form
    visible: root.mode === "form"
    width: root.contentWidth
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.yahoo
        ? "Yahoo only shares leagues with a signed-in app. This has not been tried against a real account yet.\n\n1. Create an app at developer.yahoo.com: any name, redirect URI oob (or https://localhost:8080 if it wants a web address), and Fantasy Sports read access.\n2. Paste its client ID and secret here.\n3. Open the sign-in page, allow access, and paste the code Yahoo shows."
        : String(root.chosen.detail || root.chosen.note || "")
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    TextField {
      id: inputField
      objectName: "leagueInput"
      visible: !root.yahoo
      width: parent.width
      placeholderText: String(root.chosen.placeholder || "")
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.find()
    }

    // ESPN private leagues (beta)
    Text {
      visible: root.platformId === "espn"
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Private league (beta): in a browser signed in to ESPN, open the league, then Developer Tools → Storage (Application in Chrome) → Cookies → fantasy.espn.com, and copy espn_s2 and SWID. Leave both empty for a public league."
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: s2Field
      visible: root.platformId === "espn"
      width: parent.width
      password: true
      placeholderText: "espn_s2 (private leagues only)"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.find()
    }

    TextField {
      id: swidField
      visible: root.platformId === "espn"
      width: parent.width
      password: true
      placeholderText: "SWID (private leagues only)"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.find()
    }

    // MFL private leagues (beta)
    Text {
      visible: root.platformId === "mfl"
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Private league (beta): MFL shows your API key on its developer API page while you are signed in. Leave it empty for a public league."
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: keyField
      visible: root.platformId === "mfl"
      width: parent.width
      password: true
      placeholderText: "API key (private leagues only)"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.find()
    }

    // Yahoo (beta)
    TextField {
      id: clientField
      visible: root.yahoo
      width: parent.width
      placeholderText: "Client ID"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    TextField {
      id: secretField
      visible: root.yahoo
      width: parent.width
      password: true
      placeholderText: "Client secret"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Row {
      visible: root.yahoo
      spacing: Style.space(8)

      Button {
        text: "Create a Yahoo app"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.openLink("https://developer.yahoo.com/apps/create/")
      }

      Button {
        text: "Open the sign-in page"
        enabled: Fantasy.yahooAuthUrl(clientField.text).length > 0
        opacity: enabled ? 1 : 0.4
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.openLink(Fantasy.yahooAuthUrl(clientField.text))
      }
    }

    TextField {
      id: codeField
      visible: root.yahoo
      width: parent.width
      placeholderText: "Code from Yahoo"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.find()
    }

    Button {
      text: root.busy ? (root.yahoo ? "Signing in…" : "Looking…") : (root.yahoo ? "Sign in" : "Find league")
      enabled: !root.busy
      fontFamily: root.fontFamily
      foreground: root.foreground
      bordered: true
      onClicked: root.find()
    }

    Text {
      visible: root.status.length > 0
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.status
      color: root.statusBad ? Color.urgent : root.foreground
      opacity: root.statusBad ? 1 : 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // —— What the lookup found ——
  Item {
    visible: root.mode === "pick"
    anchors.fill: parent

    Text {
      id: pickIntro
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: {
        if (root.status) return root.status
        if (root.teamPick) return String(root.found[0].name || "This league") + ": pick your team. Any team works, so you can follow a friend's."
        return "Your leagues this season. Pick the ones to follow; pick one again to drop it. Escape when done."
      }
      color: root.statusBad && root.status ? Color.urgent : root.foreground
      opacity: root.statusBad && root.status ? 1 : 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    ListView {
      id: pickList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: pickIntro.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.pickRows.length
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (count > 0 && currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: OptionRow {
        required property int index
        readonly property var row: root.pickRows[index] || ({})
        width: ListView.view.width
        selected: root.selectedIndex === index
        title: row.team ? String(row.team.name || "") : String((row.league && row.league.name) || "")
        note: row.team ? String(row.team.owner || "")
          : (row.league && row.league.teamName ? "Your team: " + row.league.teamName : "")
        tag: root.isAdded(row) ? "added" : ""
        lit: root.isAdded(row)
        hoverFill: root.hoverFill
        selectedBorder: root.borderSpec
        cornerRadius: root.cornerRadius
        fontFamily: root.fontFamily
        foreground: root.foreground
        onHovered: root.selectedIndex = index
        onPicked: root.pick(row)
      }
    }
  }
}
