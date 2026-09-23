import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "zones.js" as Zones

Item {
  id: root

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
  property var localZone: ({})

  readonly property string panelTitle: root.mode === "pick" ? "Add time zone" : ""
  readonly property var zones: Zones.normalizeZones(root.settings)
  readonly property var filtered: {
    var query = root.filterText.trim().toLowerCase()
    var have = {}
    for (var i = 0; i < root.zones.length; i++) have[root.zones[i]] = true
    var out = []
    var all = root.catalog
    for (var j = 0; j < all.length; j++) {
      var zone = all[j]
      if (!zone || have[String(zone.id || "")]) continue
      if (query && !root.matches(zone, query)) continue
      out.push(zone)
    }
    return out
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function matches(zone, query) {
    var id = String(zone.id || "").toLowerCase().replace(/_/g, " ")
    var label = String(zone.label || "").toLowerCase()
    var region = String(zone.region || "").toLowerCase()
    return label.indexOf(query) >= 0 || region.indexOf(query) >= 0 || id.indexOf(query) >= 0
  }

  function homeCount() {
    return root.zones.length + (root.zones.length < Zones.maxZones() ? 1 : 0)
  }

  function commit(ids) {
    // The settings host stores this for the widget. An empty object forgets it.
    root.settings = Zones.settingsFromZones(ids) || ({})
  }

  function addZone(id) {
    if (root.zones.length >= Zones.maxZones()) return
    var next = []
    for (var i = 0; i < root.zones.length; i++) next.push(root.zones[i])
    next.push(String(id || ""))
    root.commit(next)
    root.filterText = ""
    root.mode = "home"
    root.selectedIndex = Math.max(0, Zones.normalizeZones({ zones: next }).length - 1)
  }

  function removeZone(id) {
    var next = []
    for (var i = 0; i < root.zones.length; i++) {
      if (root.zones[i] !== id) next.push(root.zones[i])
    }
    root.commit(next)
    var count = next.length + (next.length < Zones.maxZones() ? 1 : 0)
    if (root.selectedIndex >= count) root.selectedIndex = Math.max(0, count - 1)
  }

  function openPick() {
    if (root.zones.length >= Zones.maxZones()) return
    root.mode = "pick"
    root.filterText = ""
    root.selectedIndex = 0
  }

  function handleEscape() {
    if (root.mode !== "pick") return false
    if (root.filterText) {
      root.filterText = ""
      root.selectedIndex = 0
      return true
    }
    root.mode = "home"
    root.selectedIndex = 0
    return true
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Escape) return root.handleEscape()
    if (root.mode === "home") {
      var count = root.homeCount()
      if (count < 1) return false
      if (event.key === Qt.Key_Up) {
        root.selectedIndex = (root.selectedIndex - 1 + count) % count
        return true
      }
      if (event.key === Qt.Key_Down) {
        root.selectedIndex = (root.selectedIndex + 1) % count
        return true
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.selectedIndex === root.zones.length) root.openPick()
        return true
      }
      if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
        if (root.selectedIndex < root.zones.length) root.removeZone(root.zones[root.selectedIndex])
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
      if (picked) root.addZone(picked.id)
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

  function localLine() {
    var zone = root.localZone || {}
    if (!zone.label && !zone.id) return "This computer’s clock"
    var place = String(zone.label || zone.id || "Local")
    if (zone.abbr) return "This computer · " + place + " (" + zone.abbr + ")"
    return "This computer · " + place
  }

  Process {
    id: zoneProbe
    command: ["/usr/bin/python3", root.scriptPath("zones.py")]
    stdout: StdioCollector { id: zoneOut; waitForEnd: true }
    onExited: function(exitCode) {
      var rows = []
      var ok = false
      try {
        rows = JSON.parse(zoneOut.text || "[]")
        ok = exitCode === 0 && Array.isArray(rows)
      } catch (e) { ok = false }
      root.catalog = ok ? rows : []
      root.catalogLoaded = true
      root.catalogFailed = !ok
    }
  }

  Process {
    id: localProbe
    command: ["/usr/bin/python3", root.scriptPath("zones.py"), "--local"]
    stdout: StdioCollector { id: localOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var parsed = JSON.parse(localOut.text || "{}")
        if (parsed && typeof parsed === "object") root.localZone = parsed
      } catch (e) { }
    }
  }

  Component.onCompleted: {
    zoneProbe.running = true
    localProbe.running = true
  }

  onFilterTextChanged: root.selectedIndex = 0

  Column {
    visible: root.mode === "home"
    anchors.fill: parent
    spacing: Style.spacing.md

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.localLine() + ". Add up to 3 more clocks."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.zones

        BorderSurface {
          required property int index
          required property var modelData
          width: parent.width
          height: Style.space(50)
          radius: root.cornerRadius
          color: index === root.selectedIndex ? root.hoverFill : "transparent"
          borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

          Column {
            anchors.left: parent.left
            anchors.right: removeButton.left
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Zones.cityOf(modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Zones.regionOf(modelData) || String(modelData)
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Item {
            id: removeButton
            width: Style.space(40)
            height: parent.height
            anchors.right: parent.right
            z: 2

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
              onClicked: root.removeZone(String(modelData))
            }
          }

          MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: removeButton.left
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = index
            onClicked: root.selectedIndex = index
          }
        }
      }

      BorderSurface {
        visible: root.zones.length < Zones.maxZones()
        width: parent.width
        height: Style.space(50)
        radius: root.cornerRadius
        color: root.selectedIndex === root.zones.length ? root.hoverFill : "transparent"
        borderSpec: root.selectedIndex === root.zones.length ? root.borderSpec : Border.none()

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
            text: "Add time zone"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.zones.length + " of " + Zones.maxZones()
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = root.zones.length
          onClicked: root.openPick()
        }
      }
    }

    Text {
      visible: root.zones.length >= Zones.maxZones()
      width: parent.width
      textFormat: Text.PlainText
      text: Zones.maxZones() + " of " + Zones.maxZones()
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
      text: root.filterText.length > 0 ? root.filterText : "Search cities…"
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
      text: "Time zones could not be loaded."
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
      text: "Loading time zones…"
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
        readonly property var zone: root.filtered[index] || {}
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
            text: String(zone.label || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            visible: String(zone.region || "").length > 0
            textFormat: Text.PlainText
            text: String(zone.region || "")
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
          onClicked: root.addZone(zone.id)
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
      text: root.filterText.length > 0 ? "No matches" : "Every time zone is already shown"
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
