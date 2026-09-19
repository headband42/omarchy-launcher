import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

Item {
  id: root

  property var tiles: []
  property var appLibrary: null
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
    return TileModel.resolveAll(root.tiles, root.slotCount, root.appLibrary)
  }

  // slots | picker | webapp | edit
  property string view: "slots"
  property int activeIndex: 0
  property string filterText: ""
  property int selectedIndex: 0
  property var appRows: []
  property string webName: ""
  property string webUrl: ""
  property string overrideLabel: ""
  property string overrideUrl: ""

  readonly property var activeTile: root.resolvedTiles[root.activeIndex] || { empty: true }

  function handleEscape() {
    if (root.view === "webapp") {
      root.view = "picker"
      Qt.callLater(function() { keyScope.forceActiveFocus() })
      return true
    }
    if (root.view === "picker") {
      root.view = root.activeTile.empty ? "slots" : "edit"
      root.filterText = ""
      Qt.callLater(function() { keyScope.forceActiveFocus() })
      return true
    }
    if (root.view === "edit") {
      root.persistOverride()
      root.view = "slots"
      Qt.callLater(function() { keyScope.forceActiveFocus() })
      return true
    }
    root.closed()
    return true
  }

  function persist(next) {
    root.saveTiles(next)
  }

  function replaceSlot(index, tile) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = TileModel.storedTile(tile)
    root.persist(next)
  }

  function clearSlot(index) {
    var next = TileModel.storedTiles(root.tiles, root.slotCount)
    next[index] = null
    root.persist(next)
  }

  function openSlot(index) {
    root.activeIndex = index
    root.filterText = ""
    root.selectedIndex = 0
    var tile = root.resolvedTiles[index] || { empty: true }
    if (tile.empty) {
      root.view = "picker"
      root.rebuildApps()
    } else {
      root.overrideLabel = String(tile.label || "")
      root.overrideUrl = String(tile.url || "")
      root.view = "edit"
    }
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function openPicker() {
    root.filterText = ""
    root.selectedIndex = 0
    root.view = "picker"
    root.rebuildApps()
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function rebuildApps() {
    var _rev = root.catalogRevision
    root.appRows = TileModel.listApps(root.appLibrary, root.filterText)
    if (root.selectedIndex >= root.appRows.length) root.selectedIndex = Math.max(0, root.appRows.length - 1)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuildApps()
  }

  function chooseAppRow(row) {
    var tile = TileModel.fromAppRow(row)
    if (!tile) return
    root.replaceSlot(root.activeIndex, tile)
    root.overrideLabel = String(tile.label || "")
    root.overrideUrl = String(tile.url || "")
    root.view = "edit"
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function persistOverride() {
    if (root.view !== "edit") return
    var current = TileModel.storedTile(root.resolvedTiles[root.activeIndex] || null)
    if (!current) return
    var label = String(root.overrideLabel || "").trim()
    var url = String(root.overrideUrl || "").trim()
    if (label) current.label = label
    if (url) {
      if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url)) url = "https://" + url
      current.url = url
    } else {
      delete current.url
    }
    root.replaceSlot(root.activeIndex, current)
  }

  function createWebApp() {
    var tile = TileModel.fromUrl(root.webUrl, root.webName)
    if (!tile) return
    root.replaceSlot(root.activeIndex, tile)
    if (tile.label && tile.url) {
      Util.execDetached("omarchy-webapp-install " + Util.shellQuote(tile.label) + " " + Util.shellQuote(tile.url) + " ''")
    }
    root.overrideLabel = String(tile.label || "")
    root.overrideUrl = String(tile.url || "")
    root.webName = ""
    root.webUrl = ""
    root.view = "edit"
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.handleEscape()
      return true
    }

    if (nameField.activeFocus || urlField.activeFocus || overrideUrlField.activeFocus || overrideNameField.activeFocus) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.view === "webapp") root.createWebApp()
        else if (root.view === "edit") root.handleEscape()
        return true
      }
      return false
    }

    if (root.view === "picker") {
      var count = root.appRows.length + 1
      if (event.key === Qt.Key_Up) {
        root.selectedIndex = (root.selectedIndex - 1 + count) % count
        return true
      }
      if (event.key === Qt.Key_Down) {
        root.selectedIndex = (root.selectedIndex + 1) % count
        return true
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.selectedIndex === 0) {
          root.webName = ""
          root.webUrl = ""
          root.view = "webapp"
          Qt.callLater(function() { nameField.forceActiveFocus() })
        } else {
          root.chooseAppRow(root.appRows[root.selectedIndex - 1])
        }
        return true
      }
      if (Util.editsFilter(event, root.filterText)) {
        root.setFilter(Util.editedFilter(event, root.filterText))
        return true
      }
      if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
        root.setFilter(root.filterText + event.text)
        return true
      }
    }

    return false
  }

  onVisibleChanged: {
    if (visible) {
      root.view = "slots"
      root.filterText = ""
      root.selectedIndex = 0
      root.rebuildApps()
      Qt.callLater(function() { keyScope.forceActiveFocus() })
    }
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
    Keys.onShortcutOverride: function(event) {
      if (event.key === Qt.Key_Escape) event.accepted = true
    }
    Keys.onPressed: function(event) {
      if (root.handleKey(event)) event.accepted = true
    }

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.right: doneButton.left
      anchors.rightMargin: Style.spacing.md
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.view === "picker" ? ("Slot " + (root.activeIndex + 1) + " · Widgets")
          : root.view === "webapp" ? "New web app"
          : root.view === "edit" ? ("Slot " + (root.activeIndex + 1))
          : "Tiles"
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
      id: slotList
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
          id: slotIndexText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          textFormat: Text.PlainText
          text: String(index + 1)
          color: slotMouse.containsMouse ? root.selectedText : root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Image {
          id: slotIcon
          visible: !empty && (String(tile.faviconUrl || "").length > 0 || String(tile.iconName || "").length > 0)
          width: Style.font.iconLarge
          height: Style.font.iconLarge
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: {
            if (String(tile.iconName || "").length > 0 && root.appLibrary) return root.appLibrary.iconSource(tile.iconName)
            if (String(tile.faviconUrl || "").length > 0) return tile.faviconUrl
            return ""
          }
          asynchronous: true
          cache: true
          anchors.left: slotIndexText.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: slotGlyph
          visible: !slotIcon.visible
          anchors.left: slotIndexText.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.iconLarge
          textFormat: Text.PlainText
          text: empty ? "󰣆" : String(tile.icon || "󰣆")
          color: slotMouse.containsMouse ? root.selectedText : root.foreground
          opacity: empty ? 0.4 : 1
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          horizontalAlignment: Text.AlignHCenter
        }

        Column {
          anchors.left: slotIcon.visible ? slotIcon.right : slotGlyph.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: empty ? "Empty slot" : String(tile.label || "App")
            color: slotMouse.containsMouse ? root.selectedText : root.foreground
            opacity: empty ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: empty ? "Choose a widget" : ("App · " + (tile.url || tile.desktop || tile.command || "installed app"))
            color: slotMouse.containsMouse ? root.selectedText : root.foreground
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

    Text {
      id: searchText
      visible: root.view === "picker"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Search installed apps…"
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    ListView {
      id: appList
      visible: root.view === "picker"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.appRows.length + 1
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
          color: index === root.selectedIndex ? root.selectedText : root.foreground
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

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: isNew ? "New web app" : String((row && row.name) || "")
            color: index === root.selectedIndex ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: isNew || (row && row.detail)
            textFormat: Text.PlainText
            text: isNew ? "Install a site as a launcher widget" : String((row && row.detail) || "")
            color: index === root.selectedIndex ? root.selectedText : root.foreground
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
          onClicked: {
            if (isNew) {
              root.webName = ""
              root.webUrl = ""
              root.view = "webapp"
              Qt.callLater(function() { nameField.forceActiveFocus() })
            } else {
              root.chooseAppRow(row)
            }
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
        textFormat: Text.PlainText
        text: "Creates a widget with this site’s icon and opens it as a web app. You can change the URL later."
        color: root.foreground
        opacity: 0.7
        wrapMode: Text.WordWrap
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
        text: "Add widget"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.createWebApp()
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
        text: "App widget. Default target comes from the installed app; override the URL if you want."
        color: root.foreground
        opacity: 0.7
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      TextField {
        id: overrideNameField
        width: parent.width
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        placeholderText: "Label"
        text: root.overrideLabel
        onTextChanged: root.overrideLabel = text
      }

      TextField {
        id: overrideUrlField
        width: parent.width
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.foreground
        placeholderText: activeTile.desktop ? ("Default: " + activeTile.desktop) : "URL (optional override)"
        text: root.overrideUrl
        onTextChanged: root.overrideUrl = text
      }

      Button {
        text: "Choose installed app…"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.openPicker()
      }

      Button {
        text: "New web app…"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: {
          root.webName = root.overrideLabel
          root.webUrl = root.overrideUrl
          root.view = "webapp"
          Qt.callLater(function() { nameField.forceActiveFocus() })
        }
      }

      Button {
        text: "Clear slot"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: {
          root.clearSlot(root.activeIndex)
          root.view = "slots"
        }
      }
    }
  }
}
