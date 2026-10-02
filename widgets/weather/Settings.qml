import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "weather.js" as Weather
import "../_kit/kit.js" as Kit

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

  function commit(location) {
    root.settings = Weather.settingsWith(root.settings, "location", location)
    root.forceActiveFocus()
  }

  function setUnits(units) {
    root.settings = Weather.settingsWith(root.settings, "units", units)
    root.forceActiveFocus()
  }

  function setAtmosphere(enabled) {
    root.settings = Weather.settingsWith(root.settings, "atmosphere", enabled !== false)
    root.forceActiveFocus()
  }

  function setRadarRange(range) {
    root.settings = Weather.settingsWith(root.settings, "radarRange", range)
    root.forceActiveFocus()
  }

  function togglePanel(id) {
    root.settings = Weather.togglePanel(root.settings, id)
    root.forceActiveFocus()
  }

  function useApproximate() {
    root.settings = Weather.settingsWith(root.settings, "location", null)
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
    searchProbe.command = ["/usr/bin/python3", "-u", Kit.localPath(Qt.resolvedUrl("weather.py")), "--search", searchProbe.query]
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
  implicitHeight: root.mode === "search" ? Style.space(430) : home.implicitHeight

  Component.onCompleted: root.forceActiveFocus()
  onSearchTextChanged: {
    root.selectedIndex = 0
    searchDelay.restart()
  }

  Column {
    id: home
    visible: root.mode === "home"
    width: root.contentWidth
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
          text: root.options.location ? "SAVED" : "APPROXIMATE"
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

    Column {
      width: parent.width
      spacing: Style.space(7)

      Row {
        width: parent.width

        Text {
          width: parent.width - panelCount.implicitWidth
          textFormat: Text.PlainText
          text: "Panels"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.Medium
        }

        Text {
          id: panelCount
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: root.options.panels.length === 1 ? "1 shown" : root.options.panels.length + " shown, in turn"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Grid {
        id: panelGrid
        width: parent.width
        columns: 3
        spacing: Style.space(7)

        Repeater {
          model: Weather.PANELS

          BorderSurface {
            id: panelChip
            required property var modelData
            readonly property bool shown: root.options.panels.indexOf(panelChip.modelData.id) >= 0
            // The last panel shown cannot be turned off.
            readonly property bool locked: panelChip.shown && root.options.panels.length === 1
            width: (panelGrid.width - panelGrid.spacing * 2) / 3
            height: Style.space(34)
            radius: root.cornerRadius
            color: panelChip.shown ? root.hoverFill : "transparent"
            borderSpec: panelChip.shown ? root.borderSpec : Border.none()

            Row {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: panelChip.shown ? "\uf00c" : "\uf067"
                color: root.foreground
                opacity: panelChip.shown ? 0.9 : 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: panelChip.modelData.name
                color: root.foreground
                opacity: panelChip.shown ? 1 : 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: panelChip.shown ? Font.DemiBold : Font.Normal
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: panelChip.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
              onClicked: root.togglePanel(panelChip.modelData.id)
            }
          }
        }
      }
    }

    Column {
      visible: root.options.panels.indexOf("radar") >= 0
      width: parent.width
      spacing: Style.space(7)

      Text {
        textFormat: Text.PlainText
        text: "Radar range"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
      }

      Row {
        id: rangeRow
        width: parent.width
        spacing: Style.space(7)

        Repeater {
          model: [
            { id: "local", label: "Local · 400 km" },
            { id: "regional", label: "Regional · 800 km" }
          ]

          BorderSurface {
            id: rangeChip
            required property var modelData
            readonly property bool chosen: root.options.radarRange === rangeChip.modelData.id
            width: (rangeRow.width - rangeRow.spacing) / 2
            height: Style.space(34)
            radius: root.cornerRadius
            color: rangeChip.chosen ? root.hoverFill : "transparent"
            borderSpec: rangeChip.chosen ? root.borderSpec : Border.none()

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: rangeChip.modelData.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: rangeChip.chosen ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setRadarRange(rangeChip.modelData.id)
            }
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(7)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - Style.space(56)
          spacing: 1

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Atmosphere"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Weather-tinted glow and precip on the tile background"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: root.options.atmosphere
          onToggled: root.setAtmosphere(!root.options.atmosphere)
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
          text: root.options.location ? "○" : "◉"
          color: root.foreground
          opacity: root.options.location ? 0.45 : 0.9
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
            text: root.options.location ? "Switch to approximate location" : "Using approximate location"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: root.options.location ? Font.Normal : Font.DemiBold
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.options.location
              ? "Clears the saved city and checks your public IP once per session"
              : "No saved city — IP lookup once per launcher session"
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
      text: "Forecasts and air quality come from Open-Meteo, radar from RainViewer over NASA’s night lights. Type a city name, postal code, or “City, Country” to narrow the results."
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
