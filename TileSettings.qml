import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

Item {
  id: root

  property var tiles: []
  property var appLibrary: null
  property var widgetCatalog: []
  property int catalogRevision: 0
  property int columns: 4
  property int rows: 2
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color hoverFill: Color.menu.background
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding

  signal saveTiles(var tiles)
  signal closed()

  readonly property int slotCount: Math.max(0, root.columns * root.rows)
  readonly property var resolvedTiles: {
    var _rev = root.catalogRevision
    return TileModel.resolveAll(root.tiles, root.slotCount, root.appLibrary, root.widgetCatalog)
  }
  readonly property var catalog: {
    var list = Array.isArray(root.widgetCatalog) ? root.widgetCatalog.slice() : []
    var hasNone = false
    for (var i = 0; i < list.length; i++) {
      if (!String(list[i].id || "")) { hasNone = true; break }
    }
    if (!hasNone) {
      list.unshift({
        id: "",
        name: "Icon & link",
        description: "No widget. The tile is just the icon for the app or site it opens.",
        icon: "󰖟"
      })
    }
    return list
  }

  // slots | edit | widgets | opens | webapp
  property string view: "slots"
  property int activeIndex: 0
  property string filterText: ""
  property int selectedIndex: 0
  property var appRows: []
  property int appCount: 0
  property string webName: ""
  property string webUrl: ""

  readonly property var activeTile: root.resolvedTiles[root.activeIndex] || { empty: true }

  function handleEscape() {
    if (root.view === "webapp") { root.view = "opens"; return true }
    if (root.view === "widgets" || root.view === "opens") { root.view = "edit"; return true }
    if (root.view === "edit") { root.view = "slots"; return true }
    root.closed()
    return true
  }

  function persist(next) { root.saveTiles(next) }

  function slotAt(index) {
    var source = Array.isArray(root.tiles) ? root.tiles : []
    return source[index] && typeof source[index] === "object" ? source[index] : null
  }

  function writeSlot(index, tile) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = tile
    root.persist(next)
  }

  function openSlot(index) {
    root.activeIndex = index
    root.view = "edit"
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function chooseWidget(widget) {
    root.writeSlot(root.activeIndex, TileModel.applyWidget(root.slotAt(root.activeIndex), widget))
    root.view = "edit"
  }

  function chooseLaunch(launch) {
    root.writeSlot(root.activeIndex, TileModel.applyLaunch(root.slotAt(root.activeIndex), launch))
    root.view = "edit"
  }

  function clearSlot() {
    root.writeSlot(root.activeIndex, null)
    root.view = "slots"
  }

  function rebuildApps() {
    var _rev = root.catalogRevision
    var rows = TileModel.listApps(root.appLibrary, root.filterText)
    if (!rows || rows.length === 0) rows = root.desktopEntryRows(root.filterText)
    root.appRows = rows
    root.appCount = rows.length
    if (root.selectedIndex >= rows.length + 1) root.selectedIndex = Math.max(0, rows.length)
  }

  function desktopEntryRows(query) {
    var q = String(query || "").trim().toLowerCase()
    var values = []
    try { values = DesktopEntries.applications.values } catch (e) { values = [] }
    var out = []
    if (!values) return out
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var name = String(entry.name || "")
      var id = String(entry.id || "")
      if (!name || !id) continue
      var hay = (name + " " + id + " " + String(entry.genericName || "")).toLowerCase()
      if (q && hay.indexOf(q) < 0) continue
      out.push({
        appId: id,
        name: name,
        detail: String(entry.genericName || ""),
        iconName: String(entry.icon || ""),
        url: TileModel.urlFromExec(String(entry.execString || ""))
      })
    }
    out.sort(function(a, b) {
      var an = String(a.name || "").toLowerCase()
      var bn = String(b.name || "").toLowerCase()
      if (an < bn) return -1
      if (an > bn) return 1
      return 0
    })
    return out
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuildApps()
  }

  function createWebApp() {
    var launch = TileModel.fromUrl(root.webUrl, root.webName)
    if (!launch) return
    if (launch.label && launch.url)
      Util.execDetached("omarchy-webapp-install " + Util.shellQuote(launch.label) + " " + Util.shellQuote(launch.url) + " ''")
    root.chooseLaunch(launch)
    root.webName = ""
    root.webUrl = ""
  }

  function opensLabel(tile) {
    if (!tile || tile.empty) return "Not set"
    return tile.label || tile.url || tile.desktop || tile.command || "Not set"
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) { root.handleEscape(); return true }
    if (nameField.activeFocus || urlField.activeFocus) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.view === "webapp") root.createWebApp()
        return true
      }
      return false
    }
    if (root.view === "opens") {
      var count = root.appCount + 1
      if (event.key === Qt.Key_Up) { root.selectedIndex = (root.selectedIndex - 1 + count) % count; return true }
      if (event.key === Qt.Key_Down) { root.selectedIndex = (root.selectedIndex + 1) % count; return true }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.selectedIndex === 0) { root.view = "webapp"; Qt.callLater(function() { nameField.forceActiveFocus() }) }
        else root.chooseLaunch(TileModel.fromAppRow(root.appRows[root.selectedIndex - 1]))
        return true
      }
      if (Util.editsFilter(event, root.filterText)) { root.setFilter(Util.editedFilter(event, root.filterText)); return true }
      if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
        root.setFilter(root.filterText + event.text)
        return true
      }
    }
    if (root.view === "widgets") {
      var wcount = root.catalog.length
      if (event.key === Qt.Key_Up) { root.selectedIndex = (root.selectedIndex - 1 + wcount) % wcount; return true }
      if (event.key === Qt.Key_Down) { root.selectedIndex = (root.selectedIndex + 1) % wcount; return true }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.chooseWidget(root.catalog[root.selectedIndex])
        return true
      }
    }
    return false
  }

  onVisibleChanged: if (visible) {
    root.view = "slots"
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildApps()
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }
  onViewChanged: {
    if (root.view === "opens") { root.filterText = ""; root.selectedIndex = 0; root.rebuildApps() }
    if (root.view === "widgets") root.selectedIndex = 0
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }
  onCatalogRevisionChanged: if (visible) root.rebuildApps()

  Connections {
    target: root.appLibrary
    function onAppsChanged() { if (root.visible) root.rebuildApps() }
  }

  BorderSurface {
    anchors.fill: parent
    radius: root.cornerRadius
    color: Color.menu.background
    borderSpec: root.borderSpec
  }
  MouseArea { anchors.fill: parent; onClicked: {} }

  Item {
    id: keyScope
    anchors.fill: parent
    anchors.margins: root.contentMargin
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: function(event) { if (event.key === Qt.Key_Escape) event.accepted = true }
    Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.right: doneButton.left
      anchors.rightMargin: Style.spacing.md
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.view === "widgets" ? "Launcher widgets"
          : root.view === "opens" ? ("Opens · " + root.appCount + " apps")
          : root.view === "webapp" ? "New web app"
          : root.view === "edit" ? ("Slot " + (root.activeIndex + 1))
          : "Pin widgets"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Button {
      id: doneButton
      anchors.right: parent.right
      anchors.verticalCenter: titleText.verticalCenter
      text: root.view === "slots" ? "Done" : "Back"
      fontFamily: root.fontFamily
      foreground: root.foreground
      bordered: true
      onClicked: root.handleEscape()
    }

    ListView {
      visible: root.view === "slots"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.slotCount

      delegate: BorderSurface {
        required property int index
        readonly property var tile: root.resolvedTiles[index] || { empty: true }
        readonly property bool empty: tile.empty === true
        width: ListView.view.width
        height: Style.space(58)
        radius: root.cornerRadius
        color: slotMouse.containsMouse ? root.hoverFill : "transparent"
        borderSpec: slotMouse.containsMouse ? root.borderSpec : Border.none()

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          textFormat: Text.PlainText
          text: String(index + 1)
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(36)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: empty ? "Empty slot" : String(tile.widgetName || "Icon & link")
            color: root.foreground
            opacity: empty ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: empty ? "Widget + what it opens" : ("Opens " + root.opensLabel(tile))
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        MouseArea {
          id: slotMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openSlot(index)
        }
      }
    }

    Column {
      visible: root.view === "edit"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.lg
      spacing: Style.spacing.md

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "The widget is what you see. Opens is what a click launches — they are separate."
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      BorderSurface {
        width: parent.width
        height: Style.space(58)
        radius: root.cornerRadius
        color: widgetRowMouse.containsMouse ? root.hoverFill : "transparent"
        borderSpec: root.borderSpec
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text { textFormat: Text.PlainText; text: "Widget"; color: root.foreground; opacity: 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Text { textFormat: Text.PlainText; text: String(activeTile.widgetName || "Icon & link"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; elide: Text.ElideRight; width: parent.width }
        }
        MouseArea {
          id: widgetRowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.view = "widgets"
        }
      }

      BorderSurface {
        width: parent.width
        height: Style.space(58)
        radius: root.cornerRadius
        color: opensRowMouse.containsMouse ? root.hoverFill : "transparent"
        borderSpec: root.borderSpec
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text { textFormat: Text.PlainText; text: "Opens"; color: root.foreground; opacity: 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Text { textFormat: Text.PlainText; text: root.opensLabel(activeTile); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; elide: Text.ElideRight; width: parent.width }
        }
        MouseArea {
          id: opensRowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.view = "opens"
        }
      }

      Button {
        text: "Clear slot"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: root.clearSlot()
      }
    }

    ListView {
      visible: root.view === "widgets"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      model: root.catalog.length
      currentIndex: root.selectedIndex

      delegate: BorderSurface {
        required property int index
        readonly property var modelData: root.catalog[index] || {}
        width: ListView.view.width
        height: Style.space(62)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          textFormat: Text.PlainText
          text: String(modelData.icon || "󰣆")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(40)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text { width: parent.width; textFormat: Text.PlainText; text: String(modelData.name || ""); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; elide: Text.ElideRight }
          Text { width: parent.width; textFormat: Text.PlainText; text: String(modelData.description || ""); color: root.foreground; opacity: 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; wrapMode: Text.NoWrap }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.chooseWidget(modelData)
        }
      }
    }

    Text {
      id: searchText
      visible: root.view === "opens"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Search apps to open…"
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    ListView {
      visible: root.view === "opens"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      model: root.appCount + 1
      currentIndex: root.selectedIndex

      delegate: BorderSurface {
        required property int index
        readonly property bool isNew: index === 0
        readonly property var row: isNew ? null : (root.appRows[index - 1] || null)
        width: ListView.view.width
        height: Style.space(50)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()
        Text {
          visible: isNew
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Image {
          visible: !isNew && row && String(row.iconName || "").length > 0
          width: Style.font.iconLarge
          height: Style.font.iconLarge
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: visible && root.appLibrary ? root.appLibrary.iconSource(row.iconName) : ""
          asynchronous: true
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(40)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text { width: parent.width; textFormat: Text.PlainText; text: isNew ? "New web app" : String((row && row.name) || ""); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; elide: Text.ElideRight }
          Text { width: parent.width; visible: isNew || (row && row.detail); textFormat: Text.PlainText; text: isNew ? "Open a site as a web app" : String((row && row.detail) || ""); color: root.foreground; opacity: 0.55; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: {
            if (isNew) { root.view = "webapp"; Qt.callLater(function() { nameField.forceActiveFocus() }) }
            else root.chooseLaunch(TileModel.fromAppRow(row))
          }
        }
      }
    }

    Column {
      visible: root.view === "webapp"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.lg
      spacing: Style.spacing.md
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "This is only what a click opens. It does not change the widget."
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      TextField {
        id: nameField
        width: parent.width
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        placeholderText: "Name"
        text: root.webName
        onTextChanged: root.webName = text
      }
      TextField {
        id: urlField
        width: parent.width
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        placeholderText: "https://…"
        text: root.webUrl
        onTextChanged: root.webUrl = text
        onAccepted: root.createWebApp()
      }
      Button {
        text: "Use this site"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.createWebApp()
      }
    }
  }
}
