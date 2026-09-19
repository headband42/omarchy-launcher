import QtQuick
import qs.Commons
import qs.Ui
import "TileModel.js" as TileModel

BorderSurface {
  id: root

  property var appLibrary: null
  property int catalogRevision: 0
  property int slotIndex: 0
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property int contentMargin: Style.spacing.panelPadding

  signal chosen(var tile)
  signal cleared()
  signal cancelled()

  radius: Style.cornerRadius
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  property string filterText: ""
  property string urlText: ""
  property int selectedIndex: 0
  property bool cursorActive: true

  ListModel { id: appModel }

  function rebuild() {
    var _rev = root.catalogRevision
    appModel.clear()
    if (!root.appLibrary) return
    var rows = root.appLibrary.sortedEntries(root.filterText)
    var limit = Math.min(rows.length, 80)
    for (var i = 0; i < limit; i++) {
      var entry = rows[i] && rows[i].entry
      if (!entry) continue
      appModel.append({
        appId: String(entry.id || ""),
        name: root.appLibrary.entryName(entry),
        detail: root.appLibrary.entrySubtext(entry),
        iconName: String(entry.icon || "")
      })
    }
    if (appModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= appModel.count) root.selectedIndex = appModel.count - 1
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.rebuild()
  }

  function chooseIndex(index) {
    if (index < 0 || index >= appModel.count) return
    var row = appModel.get(index)
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    var entry = null
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].entry && String(rows[i].entry.id || "") === row.appId) {
        entry = rows[i].entry
        break
      }
    }
    var tile = TileModel.fromDesktopEntry(entry, root.appLibrary)
    if (!tile && row) tile = { type: "app", desktop: TileModel.normalizeDesktopId(row.appId), label: row.name, iconName: row.iconName }
    if (tile) root.chosen(tile)
  }

  function chooseUrl() {
    var tile = TileModel.fromUrl(root.urlText)
    if (tile) root.chosen(tile)
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancelled()
      return true
    }
    if (urlField.activeFocus) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.chooseUrl()
        return true
      }
      return false
    }
    if (event.key === Qt.Key_Up) {
      if (appModel.count > 0)
        root.selectedIndex = (root.selectedIndex - 1 + appModel.count) % appModel.count
      return true
    }
    if (event.key === Qt.Key_Down) {
      if (appModel.count > 0)
        root.selectedIndex = (root.selectedIndex + 1) % appModel.count
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (appModel.count > 0) root.chooseIndex(root.selectedIndex)
      else root.chooseUrl()
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
    return false
  }

  onVisibleChanged: {
    if (visible) {
      root.filterText = ""
      root.urlText = ""
      root.selectedIndex = 0
      root.rebuild()
      Qt.callLater(function() { searchFocus.forceActiveFocus() })
    }
  }

  onCatalogRevisionChanged: if (visible) root.rebuild()

  Item {
    id: searchFocus
    anchors.fill: parent
    anchors.margins: root.contentMargin
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (root.handleKey(event)) event.accepted = true
    }

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: "Slot " + (root.slotIndex + 1) + " · Application"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      id: searchText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: titleText.bottom
      anchors.topMargin: Style.spacing.md
      textFormat: Text.PlainText
      text: root.filterText.length > 0 ? root.filterText : "Search apps…"
      color: root.foreground
      opacity: root.filterText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    Row {
      id: actionRow
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: Style.spacing.sm

      Button {
        text: "Clear slot"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: root.cleared()
      }

      Button {
        text: "Back"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: root.cancelled()
      }
    }

    TextField {
      id: urlField
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: actionRow.top
      anchors.bottomMargin: Style.spacing.sm
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      foreground: root.foreground
      placeholderText: "Or paste a URL…"
      text: root.urlText
      onTextChanged: root.urlText = text
      onAccepted: root.chooseUrl()
    }

    ListView {
      id: appList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchText.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: urlField.top
      anchors.bottomMargin: Style.spacing.sm
      clip: true
      model: appModel
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selectedIndex

        delegate: BorderSurface {
          required property int index
          required property string appId
          required property string name
          required property string detail
          required property string iconName

          width: ListView.view.width
          height: Style.space(44)
          radius: Style.cornerRadius
          color: index === root.selectedIndex ? root.selectedBackground : "transparent"
          borderSpec: index === root.selectedIndex ? Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0) : Border.none()

          Image {
            width: Style.font.iconLarge
            height: Style.font.iconLarge
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            source: iconName && root.appLibrary ? root.appLibrary.iconSource(iconName) : ""
            asynchronous: true
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(36)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: name
            color: index === root.selectedIndex ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = index
            onClicked: root.chooseIndex(index)
          }
        }
    }
  }
}
