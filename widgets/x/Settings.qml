import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
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
  property string cookiesDraft: ""

  readonly property var options: X.normalizedSettings(root.settings)
  readonly property string panelTitle: root.mode === "place" ? "Choose place" : ""
  readonly property int contentWidth: Style.space(360)
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
    root.commit(X.settingsFor(row.woeid, row.name, root.options.maxHeadlines, root.options.cookiesPath, row.countryCode))
    root.mode = "home"
    root.filterText = ""
    root.selectedIndex = 0
  }

  function setMax(value) {
    root.commit(X.settingsFor(root.options.woeid, root.options.placeName, value, root.options.cookiesPath, root.options.countryCode))
  }

  function setCookiesPath(value) {
    root.commit(X.settingsFor(root.options.woeid, root.options.placeName, root.options.maxHeadlines, value, root.options.countryCode))
  }

  function clearCookies() {
    root.cookiesDraft = ""
    root.commit(X.settingsFor(root.options.woeid, root.options.placeName, root.options.maxHeadlines, "", root.options.countryCode))
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
    root.cookiesDraft = root.options.cookiesPath
    root.loadPlaces()
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

  Column {
    id: home
    visible: root.mode === "home"
    width: root.contentWidth
    spacing: Style.space(10)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Headlines use X guest trends (cookie-less). Today's News articles and notification badges need an optional cookies file — never commit secrets."
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

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
          anchors.right: chevron.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(8)
          textFormat: Text.PlainText
          text: root.options.placeName + " · " + root.options.woeid
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
        text: "COOKIES PATH (OPTIONAL)"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Netscape cookies.txt or JSON {\"auth_token\",\"ct0\"}. Keep outside the repo."
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Rectangle {
        width: parent.width
        height: Style.space(36)
        radius: root.cornerRadius
        color: root.hoverFill
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

        TextInput {
          id: cookiesInput
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          verticalAlignment: Text.AlignVCenter
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          clip: true
          text: root.cookiesDraft
          selectByMouse: true
          onTextChanged: root.cookiesDraft = text
          onEditingFinished: root.setCookiesPath(root.cookiesDraft)
          Keys.onReturnPressed: root.setCookiesPath(root.cookiesDraft)
        }
      }

      Row {
        spacing: Style.space(8)
        visible: root.options.cookiesPath !== ""

        Text {
          textFormat: Text.PlainText
          text: "Clear cookies path"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearCookies()
          }
        }
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
