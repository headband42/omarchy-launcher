import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "weather.js" as Weather

Item {
  id: root
  focus: true

  property var tile: ({})
  property var settings: ({})
  property var host: ({})
  property string fontFamily: Style.menuFamily
  property color foreground: Color.menu.text
  property color hoverFill: Color.menu.background
  property var borderSpec: Border.none()
  property int cornerRadius: Style.cornerRadius

  property string mode: "home"
  property string searchText: ""
  property int selectedIndex: 0
  property var rows: []
  property bool searchLoaded: false
  property bool searchFailed: false

  readonly property var options: Weather.normalizedSettings(root.settings)
  readonly property string panelTitle: root.mode === "search" ? "Choose weather location" : ""
  readonly property int contentWidth: Style.space(360)
  readonly property string currentLocation: root.options.location
    ? String(root.options.location.name || "Saved location")
    : "Approximate location"

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function commit(location) {
    root.settings = Weather.settingsFor(location, root.options.units)
    root.forceActiveFocus()
  }

  function setUnits(units) {
    root.settings = Weather.settingsFor(root.options.location, units)
    root.forceActiveFocus()
  }

  function useApproximate() {
    root.settings = Weather.settingsFor(null, root.options.units)
    root.forceActiveFocus()
  }

  function openSearch() {
    root.mode = "search"
    root.searchText = ""
    root.rows = []
    root.selectedIndex = 0
    root.searchLoaded = false
    root.searchFailed = false
    root.forceActiveFocus()
  }

  function beginSearch() {
    if (root.searchText.trim().length < 2) {
      root.rows = []
      root.searchLoaded = false
      root.searchFailed = false
      return
    }
    if (searchProbe.running) {
      searchProbe.again = true
      return
    }
    searchProbe.query = root.searchText.trim()
    searchProbe.command = ["/usr/bin/python3", root.scriptPath("sample.py"), "--search", searchProbe.query]
    searchProbe.running = true
  }

  function choose(row) {
    if (!row || row.latitude === undefined || row.longitude === undefined) return
    root.commit(row)
    root.mode = "home"
    root.searchText = ""
    root.rows = []
    root.forceActiveFocus()
  }

  function handleEscape() {
    if (root.mode !== "search") return false
    if (root.searchText) {
      root.searchText = ""
      root.rows = []
      root.searchLoaded = false
      root.searchFailed = false
      return true
    }
    root.mode = "home"
    root.selectedIndex = 0
    root.forceActiveFocus()
    return true
  }

  function handleKey(event) {
    if (!event) return false
    if (root.mode === "home") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
        root.openSearch()
        return true
      }
      if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
          && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        root.openSearch()
        root.searchText = event.text
        return true
      }
      return false
    }
    if (event.key === Qt.Key_Escape) return root.handleEscape()
    var count = root.rows.length
    if (event.key === Qt.Key_Up && count > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + count) % count
      return true
    }
    if (event.key === Qt.Key_Down && count > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % count
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && count > 0) {
      root.choose(root.rows[root.selectedIndex])
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      root.searchText = root.searchText.slice(0, -1)
      root.selectedIndex = 0
      return true
    }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
      root.searchText += event.text
      root.selectedIndex = 0
      return true
    }
    return false
  }

  Process {
    id: searchProbe
    property bool again: false
    property string query: ""
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: {
      if (searchProbe.query !== root.searchText.trim()) {
        searchProbe.again = root.searchText.trim().length >= 2
        if (searchProbe.again) Qt.callLater(root.beginSearch)
        return
      }
      if (searchProbe.again) {
        searchProbe.again = false
        Qt.callLater(root.beginSearch)
        return
      }
      var parsed = null
      try { parsed = JSON.parse(searchOut.text || "[]") } catch (e) { parsed = null }
      if (parsed && Array.isArray(parsed)) {
        root.rows = parsed
        root.searchLoaded = true
        root.searchFailed = false
      } else {
        root.rows = []
        root.searchLoaded = true
        root.searchFailed = true
      }
    }
  }

  Timer {
    id: searchDelay
    interval: 280
    onTriggered: root.beginSearch()
  }

  implicitWidth: root.contentWidth
  implicitHeight: root.mode === "search" ? Style.space(430) : Style.space(300)

  Component.onCompleted: root.forceActiveFocus()
  onSearchTextChanged: {
    root.selectedIndex = 0
    searchDelay.restart()
  }

  Column {
    id: home
    visible: root.mode === "home"
    width: root.contentWidth
    height: parent.height
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Forecast location"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.weight: Font.Medium
    }

    BorderSurface {
      id: locationRow
      width: parent.width
      height: Style.space(66)
      radius: root.cornerRadius
      color: root.hoverFill
      borderSpec: root.borderSpec

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "CURRENT"
          color: root.foreground
          opacity: 0.48
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: 0.8
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.currentLocation
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openSearch()
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(7)

      Text {
        textFormat: Text.PlainText
        text: "Units"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
      }

      Row {
        id: unitsRow
        width: parent.width
        spacing: Style.space(7)

        BorderSurface {
          width: (unitsRow.width - unitsRow.spacing) / 2
          height: Style.space(38)
          radius: root.cornerRadius
          color: root.options.units === "imperial" ? root.hoverFill : "transparent"
          borderSpec: root.options.units === "imperial" ? root.borderSpec : Border.none()

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "°F · mph"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.options.units === "imperial" ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.setUnits("imperial")
          }
        }

        BorderSurface {
          width: (unitsRow.width - unitsRow.spacing) / 2
          height: Style.space(38)
          radius: root.cornerRadius
          color: root.options.units === "metric" ? root.hoverFill : "transparent"
          borderSpec: root.options.units === "metric" ? root.borderSpec : Border.none()

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "°C · km/h"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.options.units === "metric" ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.setUnits("metric")
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
        id: approximateRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(9)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "◉"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          width: approximateRow.width - approximateRow.spacing - Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Use approximate location"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Checks your public IP once per launcher session"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.useApproximate()
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Forecasts come from Open-Meteo. Type a city name, postal code, or “City, Country” to narrow the results."
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Item {
    id: searchPanel
    visible: root.mode === "search"
    width: root.contentWidth
    height: parent.height

    Text {
      id: query
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.searchText.length ? root.searchText : "Search cities…"
      color: root.foreground
      opacity: root.searchText.length ? 1 : 0.52
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: query.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.searchText.length < 2
        ? "Type at least two letters"
        : (root.searchFailed ? "Locations could not be loaded" : (root.searchLoaded && root.rows.length === 0 ? "No matching locations" : "Use ↑ ↓ and Enter"))
      color: root.foreground
      opacity: 0.56
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    ListView {
      id: resultList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: query.bottom
      anchors.topMargin: Style.space(46)
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.space(5)
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows.length
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: {
        if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)
      }

      delegate: BorderSurface {
        required property int index
        readonly property var result: (root.rows[index] || {})
        width: ListView.view.width
        height: Style.space(58)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(result.name || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: index === root.selectedIndex ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(result.detail || result.timezone || "")
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
          onClicked: root.choose(result)
        }
      }
    }
  }
}
