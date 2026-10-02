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
  property var rows: []
  property bool catalogLoaded: false
  property bool catalogFailed: false

  readonly property int teamId: {
    var n = Number(root.settings && root.settings.teamId)
    if (!isFinite(n) || n <= 0) return 0
    return Math.round(n)
  }
  readonly property bool teamColors: !!(root.settings && root.settings.teamColors)
  readonly property var current: {
    for (var i = 0; i < root.rows.length; i++) {
      if (Number(root.rows[i].id) === root.teamId) return root.rows[i]
    }
    return null
  }
  readonly property int contentWidth: Style.space(340)
  // The slate row is always first, so "no club" is one keystroke away and
  // never a hidden clear button.
  readonly property var shown: {
    var query = root.filterText.trim().toLowerCase()
    var slate = [{
      id: 0,
      abbr: "",
      full: "Week slate",
      name: "",
      nickname: "",
      divisionName: "Every game this week",
      conference: "",
      color: "",
      alt: ""
    }]
    var matches = []
    for (var i = 0; i < root.rows.length; i++) {
      var row = root.rows[i]
      if (!query) { matches.push(row); continue }
      var haystack = (String(row.abbr) + " " + String(row.full) + " " + String(row.divisionName)).toLowerCase()
      if (haystack.indexOf(query) >= 0) matches.push(row)
    }
    return slate.concat(matches)
  }
  readonly property var selected: root.shown.length ? root.shown[Math.min(root.selectedIndex, root.shown.length - 1)] : null

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function commit(id, colors) {
    var next = { teamColors: colors !== false }
    if (Number(id) > 0) next.teamId = Math.round(Number(id))
    root.settings = next
    root.forceActiveFocus()
  }

  function choose(row) {
    if (!row) return
    root.commit(Number(row.id) || 0, root.teamColors)
  }

  function clearTeam() {
    root.settings = ({})
    root.selectedIndex = 0
    root.forceActiveFocus()
  }

  function toggleColors() {
    if (root.teamId < 1) return
    root.commit(root.teamId, !root.teamColors)
  }

  function handleEscape() {
    if (!root.filterText) return false
    root.filterText = ""
    root.selectedIndex = 0
    return true
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.shown.length
    if (event.key === Qt.Key_Up && count > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + count) % count
      return true
    }
    if (event.key === Qt.Key_Down && count > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % count
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.choose(root.selected)
      return true
    }
    if (event.key === Qt.Key_Delete) {
      root.clearTeam()
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      root.filterText = root.filterText.slice(0, -1)
      root.selectedIndex = 0
      return true
    }
    if (event.key === Qt.Key_Space && root.selected && Number(root.selected.id) === root.teamId) {
      root.toggleColors()
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
        var rows = parsed && parsed.rows && parsed.rows.length ? parsed.rows : []
        if (rows.length) {
          root.rows = rows
          ok = exitCode === 0
        }
      } catch (e) { ok = false }
      if (!ok) root.rows = []
      root.catalogLoaded = true
      root.catalogFailed = !ok
    }
  }

  implicitWidth: body.implicitWidth
  implicitHeight: body.implicitHeight

  Component.onCompleted: {
    teamProbe.running = true
    root.forceActiveFocus()
  }
  onFilterTextChanged: root.selectedIndex = 0

  Column {
    id: body
    width: root.contentWidth
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Club"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.weight: Font.Medium
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "A club shows its own game, record, and playoff seed. No club shows every game this week. Delete clears it."
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      height: Style.space(34)

      BorderSurface {
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.filterText ? root.hoverFill : "transparent"
        borderSpec: root.filterText ? root.borderSpec : Border.none()

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          textFormat: Text.PlainText
          text: root.filterText ? root.filterText : "Filter clubs"
          color: root.foreground
          opacity: root.filterText ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(250)
      clip: true

      Text {
        anchors.fill: parent
        visible: root.catalogLoaded && root.shown.length < 2
        textFormat: Text.PlainText
        text: root.catalogFailed ? "Clubs could not be loaded" : "No club matches"
        color: root.foreground
        opacity: 0.58
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
      }

      ListView {
        id: clubList
        anchors.fill: parent
        clip: true
        spacing: Style.space(3)
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown
        currentIndex: root.selectedIndex
        onCurrentIndexChanged: {
          if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)
        }

        delegate: BorderSurface {
          required property int index
          required property var modelData
          width: ListView.view.width
          height: Style.space(38)
          radius: root.cornerRadius
          color: index === root.selectedIndex ? root.hoverFill : "transparent"
          borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Rectangle {
              width: 8
              height: 8
              radius: 4
              anchors.verticalCenter: parent.verticalCenter
              visible: String(modelData.color || "") !== ""
              color: String(modelData.color || "")

              Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 3
                radius: 1.5
                color: String(modelData.alt || "")
              }
            }

            Column {
              width: Math.max(0, parent.width - Style.space(36))
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.full || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: (index === root.selectedIndex
                              || Number(modelData.id) === root.teamId) ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.divisionName || "")
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                elide: Text.ElideRight
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: Number(modelData.id) === root.teamId && root.teamId > 0
              textFormat: Text.PlainText
              text: "PICKED"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, Style.font.caption - 3)
              font.weight: Font.DemiBold
              font.letterSpacing: 0.6
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = index
            onClicked: root.choose(modelData)
          }
        }
      }
    }

    BorderSurface {
      width: parent.width
      height: Style.space(48)
      radius: root.cornerRadius
      color: "transparent"
      borderSpec: Border.none()

      Row {
        id: colorsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(9)

        Column {
          width: colorsRow.width - Style.space(64)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Team colors"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.teamId > 0 ? "Space toggles it" : "Pick a club first"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        BorderSurface {
          width: Style.space(48)
          height: Style.space(26)
          anchors.verticalCenter: parent.verticalCenter
          radius: Style.space(13)
          color: root.teamColors && root.teamId > 0 ? root.hoverFill : "transparent"
          borderSpec: root.teamColors && root.teamId > 0 ? root.borderSpec : Border.none()

          Rectangle {
            id: knob
            width: 18
            height: 18
            radius: 9
            y: (parent.height - height) / 2
            x: (root.teamColors && root.teamId > 0)
              ? parent.width - width - y
              : y
            color: root.foreground
            opacity: root.teamId > 0 ? (root.teamColors ? 0.9 : 0.35) : 0.2

            Behavior on x {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.teamId > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggleColors()
      }
    }
  }
}
