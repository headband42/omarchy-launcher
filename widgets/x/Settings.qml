import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "x.js" as X

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
  property var places: []
  property bool placesLoaded: false
  property bool placesFailed: false
  property bool importing: false
  property string importStatus: ""

  readonly property var options: X.normalizedSettings(root.settings)
  readonly property string panelTitle: root.mode === "place" ? "Choose place" : ""
  readonly property int contentWidth: Style.space(360)

  // TileSettings sizes the panel from these. Without them the sheet keeps its
  // default height and the rows below spill past it.
  implicitWidth: root.contentWidth
  implicitHeight: root.mode === "place" ? Style.space(430) : home.implicitHeight
  readonly property var filteredPlaces: {
    var query = root.filterText.trim().toLowerCase()
    var rows = root.places.length ? root.places : X.placePresets()
    if (!query) return rows
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var hay = (String(row.name || "") + " " + String(row.country || "") + " " + String(row.countryCode || "") + " " + String(row.woeid || "")).toLowerCase()
      if (hay.indexOf(query) >= 0) out.push(row)
    }
    return out
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function commit(next) {
    root.settings = next || ({})
  }

  function setPlace(row) {
    if (!row) return
    root.commit(X.settingsFor(row.woeid, row.name, root.options.maxHeadlines, root.options.cookiesPath, row.countryCode, root.options.sessionAt))
    root.mode = "home"
    root.filterText = ""
    root.selectedIndex = 0
  }

  // Back to Worldwide, the place a fresh tile starts on.
  function clearPlace() {
    root.commit(X.settingsFor(1, "", root.options.maxHeadlines, root.options.cookiesPath, "", root.options.sessionAt))
    root.mode = "home"
    root.filterText = ""
    root.selectedIndex = 0
  }

  function setMax(value) {
    root.commit(X.settingsFor(root.options.woeid, root.options.placeName, value, root.options.cookiesPath, root.options.countryCode, root.options.sessionAt))
  }

  function lastJson(raw) {
    var lines = String(raw || "").trim().split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (!line) continue
      try {
        return JSON.parse(line)
      } catch (e) {}
    }
    return null
  }

  function startCookieJob(mode) {
    if (cookieJob.running) return
    cookieJob.mode = mode
    var args = ["/usr/bin/python3", "-u", root.scriptPath("export-browser-cookies.py")]
    args.push(mode === "check" ? "--check" : "--quiet")
    cookieJob.command = args
    cookieJob.running = true
  }

  function importSession() {
    if (root.importing || cookieJob.running) return
    root.importing = true
    root.importStatus = ""
    root.startCookieJob("import")
  }

  function openPlace() {
    root.mode = "place"
    root.filterText = ""
    root.selectedIndex = 0
    if (!root.placesLoaded) root.loadPlaces()
  }

  function loadPlaces() {
    if (placesProbe.running) {
      placesProbe.again = true
      return
    }
    placesProbe.command = ["/usr/bin/python3", "-u", root.scriptPath("sample.py"), "--places"]
    placesProbe.running = true
  }

  function handleEscape() {
    if (root.mode === "place") {
      root.mode = "home"
      root.filterText = ""
      return true
    }
    return false
  }

  function handleKey(event) {
    if (root.mode !== "place") return false
    if (event.key === Qt.Key_Up) {
      root.selectedIndex = Math.max(0, root.selectedIndex - 1)
      event.accepted = true
      return true
    }
    if (event.key === Qt.Key_Down) {
      root.selectedIndex = Math.min(Math.max(0, root.filteredPlaces.length - 1), root.selectedIndex + 1)
      event.accepted = true
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.filteredPlaces[root.selectedIndex]) root.setPlace(root.filteredPlaces[root.selectedIndex])
      event.accepted = true
      return true
    }
    return false
  }

  Component.onCompleted: {
    root.loadPlaces()
    root.startCookieJob("check")
  }

  Process {
    id: placesProbe
    property bool again: false
    stdout: StdioCollector { id: placesOut; waitForEnd: true }
    onExited: {
      try {
        var parsed = JSON.parse(placesOut.text || "{}")
        var rows = (parsed && parsed.places) || []
        root.places = rows && rows.length ? rows : X.placePresets()
        root.placesLoaded = true
        root.placesFailed = !(parsed && parsed.ok)
      } catch (e) {
        root.places = X.placePresets()
        root.placesLoaded = true
        root.placesFailed = true
      }
      if (placesProbe.again) {
        placesProbe.again = false
        root.loadPlaces()
      }
    }
  }

  Process {
    id: cookieJob
    property string mode: ""
    stdout: StdioCollector { id: cookieOut; waitForEnd: true }
    onExited: {
      var parsed = root.lastJson(cookieOut.text)
      if (cookieJob.mode === "check") {
        if (parsed && parsed.present && !root.importStatus) root.importStatus = "Session ready"
        return
      }
      root.importing = false
      if (parsed && parsed.ok) {
        root.importStatus = "Imported from " + String(parsed.browserName || "browser")
        root.commit(X.settingsFor(
          root.options.woeid,
          root.options.placeName,
          root.options.maxHeadlines,
          X.DEFAULT_COOKIES_PATH,
          root.options.countryCode,
          Date.now()
        ))
        return
      }
      root.importStatus = String((parsed && parsed.error) || "Could not import")
    }
  }

  Column {
    id: home
    visible: root.mode === "home"
    width: root.contentWidth
    spacing: Style.space(10)

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: "PLACE"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

      Rectangle {
        width: parent.width
        height: Style.space(36)
        radius: root.cornerRadius
        color: root.hoverFill
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

        Text {
          anchors.left: parent.left
          anchors.right: clearButton.visible ? clearButton.left : chevron.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(8)
          textFormat: Text.PlainText
          text: root.options.placeName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          id: chevron
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "›"
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openPlace()
        }

        // Above the field's MouseArea, so clearing does not also open the list.
        IconButton {
          id: clearButton
          visible: !X.isWorldwide(root.options.woeid)
          anchors.right: chevron.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰅖"
          glyphSize: Style.font.body
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.clearPlace()
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Guest trends only. Today's News is the same everywhere."
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: "MAX HEADLINES"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

      Row {
        spacing: Style.space(6)
        Repeater {
          model: [5, 8, 10]
          Rectangle {
            required property int modelData
            width: Style.space(44)
            height: Style.space(28)
            radius: Style.space(6)
            color: root.options.maxHeadlines === modelData
                   ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                   : root.hoverFill
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setMax(modelData)
            }
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: "TODAY'S NEWS"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

      Rectangle {
        width: parent.width
        height: Style.space(36)
        radius: root.cornerRadius
        color: root.hoverFill
        opacity: root.importing ? 0.55 : 1
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.importing ? "Importing…" : "Import from browser"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          enabled: !root.importing
          cursorShape: root.importing ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: root.importSession()
        }
      }

      Text {
        visible: root.importStatus !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: root.importStatus
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  Column {
    id: placePanel
    visible: root.mode === "place"
    width: root.contentWidth
    spacing: Style.space(8)

    Rectangle {
      width: parent.width
      height: Style.space(36)
      radius: root.cornerRadius
      color: root.hoverFill
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      TextInput {
        id: query
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        verticalAlignment: Text.AlignVCenter
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        focus: root.mode === "place"
        text: root.filterText
        onTextChanged: {
          root.filterText = text
          root.selectedIndex = 0
        }
      }
    }

    Text {
      visible: root.placesFailed
      width: parent.width
      textFormat: Text.PlainText
      text: "Live place list unavailable — showing presets."
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    ListView {
      id: placeList
      width: parent.width
      height: Style.space(240)
      clip: true
      model: root.filteredPlaces
      currentIndex: root.selectedIndex
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: placeList.width
        height: Style.space(34)
        radius: Style.space(4)
        color: index === root.selectedIndex
               ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
               : "transparent"

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: 0

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData.name || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: [modelData.countryCode, modelData.placeType, "woeid " + modelData.woeid].filter(function (part) { return !!part }).join(" · ")
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Math.max(10, Style.font.caption - 1)
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.setPlace(modelData)
        }
      }
    }
  }
}
