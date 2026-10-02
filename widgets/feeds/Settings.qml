import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/kit.js" as Kit
import "feeds.js" as Feeds

// The feeds on the tile. Typing searches the suggested feeds; a feed's URL,
// or any page that links to one, adds that feed.
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
  property var catalog: []
  property var defaults: []
  property bool probing: false
  property string probeError: ""

  readonly property string panelTitle: root.mode === "pick" ? "Add feed" : ""
  readonly property int contentWidth: Style.space(380)
  readonly property var picked: Feeds.feeds(root.settings) || root.defaults
  readonly property bool full: root.picked.length >= Feeds.MAX_FEEDS
  readonly property int homeCount: root.picked.length + (root.full ? 0 : 1)
  readonly property bool offerUrl: Feeds.looksLikeUrl(root.searchText)
  readonly property var matches: Feeds.filterCatalog(root.catalog, root.searchText, root.picked)
  readonly property int pickCount: root.matches.length + (root.offerUrl ? 1 : 0)

  implicitWidth: root.contentWidth
  implicitHeight: root.mode === "pick" ? Style.space(430) : home.implicitHeight

  function commit(list) {
    root.settings = Feeds.settingsFrom(list)
  }

  function add(item) {
    if (root.full) return
    root.commit(Feeds.withAdded(root.picked, item))
    root.mode = "home"
    root.searchText = ""
    root.probeError = ""
    root.selectedIndex = Math.max(0, root.picked.length - 1)
    root.forceActiveFocus()
  }

  function removeAt(index) {
    root.commit(Feeds.withRemoved(root.picked, index))
    var count = root.picked.length + (root.full ? 0 : 1)
    if (root.selectedIndex >= count) root.selectedIndex = Math.max(0, count - 1)
  }

  function openPick() {
    if (root.full) return
    root.mode = "pick"
    root.searchText = ""
    root.probeError = ""
    root.selectedIndex = 0
    searchLine.text = ""
    searchLine.forceActiveFocus()
  }

  function pickAt(index) {
    if (root.offerUrl) {
      if (index === 0) return root.probe()
      index -= 1
    }
    var row = root.matches[index]
    if (row && !row.added) root.add(row.id)
  }

  function probe() {
    if (probeProc.running) return
    root.probing = true
    root.probeError = ""
    probeProc.command = ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("feeds.py")), "--probe", root.searchText.trim()]
    probeProc.running = true
  }

  function isTyping(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
      && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
  }

  function handleEscape() {
    if (root.mode !== "pick") return false
    if (root.searchText) {
      searchLine.text = ""
      return true
    }
    root.mode = "home"
    root.selectedIndex = root.picked.length
    return true
  }

  function handleKey(event) {
    if (!event) return false
    if (event.key === Qt.Key_Escape) return root.handleEscape()
    if (root.mode === "home") {
      var count = root.homeCount
      if (event.key === Qt.Key_Up && count > 0) {
        root.selectedIndex = (root.selectedIndex - 1 + count) % count
        return true
      }
      if (event.key === Qt.Key_Down && count > 0) {
        root.selectedIndex = (root.selectedIndex + 1) % count
        return true
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (root.selectedIndex >= root.picked.length) root.openPick()
        return true
      }
      if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
        if (root.selectedIndex < root.picked.length) root.removeAt(root.selectedIndex)
        return true
      }
      if (root.isTyping(event) && !root.full) {
        root.openPick()
        searchLine.text = event.text
        return true
      }
      return false
    }
    var listed = root.pickCount
    if (event.key === Qt.Key_Up && listed > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + listed) % listed
      return true
    }
    if (event.key === Qt.Key_Down && listed > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % listed
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && listed > 0) {
      root.pickAt(root.selectedIndex)
      return true
    }
    return false
  }

  onSearchTextChanged: {
    root.selectedIndex = 0
    root.probeError = ""
  }

  Component.onCompleted: root.forceActiveFocus()

  Poller {
    script: Qt.resolvedUrl("feeds.py")
    args: ["--catalog"]
    interval: 0
    onSampled: function(data) {
      if (!data || data.ok !== true) return
      root.catalog = data.feeds || []
      root.defaults = data.defaults || []
    }
  }

  Process {
    id: probeProc
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      root.probing = false
      var data = null
      try { data = JSON.parse(probeOut.text || "") } catch (e) { data = null }
      if (!data || data.ok !== true) {
        root.probeError = data && data.error ? String(data.error) : "That site did not answer"
        return
      }
      root.add({ url: String(data.url), name: String(data.name) })
    }
  }

  component Choice: BorderSurface {
    id: choice
    property bool selected: false
    property string title: ""
    property string note: ""
    property bool dim: false
    signal picked()
    signal hovered()
    width: parent ? parent.width : 0
    height: Style.space(46)
    radius: root.cornerRadius
    color: choice.selected ? root.hoverFill : "transparent"
    borderSpec: choice.selected ? root.borderSpec : Border.none()

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(44)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: choice.title
        color: root.foreground
        opacity: choice.dim ? 0.45 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text.length > 0
        textFormat: Text.PlainText
        text: choice.note
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
      cursorShape: choice.dim ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: choice.hovered()
      onClicked: choice.picked()
    }
  }

  Column {
    id: home
    visible: root.mode === "home"
    width: root.contentWidth
    spacing: Style.spacing.md

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Up to " + Feeds.MAX_FEEDS + " feeds. The tile mixes their headlines, newest first."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.picked

        Item {
          required property int index
          required property var modelData
          width: parent.width
          height: Style.space(46)

          Choice {
            anchors.fill: parent
            selected: index === root.selectedIndex
            title: Feeds.nameFor(modelData, root.catalog)
            note: typeof modelData === "object" ? String(modelData.url) : ""
            onHovered: root.selectedIndex = index
            onPicked: root.selectedIndex = index
          }

          IconButton {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅖"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.removeAt(index)
          }
        }
      }

      Choice {
        visible: !root.full
        selected: root.selectedIndex === root.picked.length
        title: "Add feed"
        note: root.picked.length + " of " + Feeds.MAX_FEEDS + " · or just start typing"
        onHovered: root.selectedIndex = root.picked.length
        onPicked: root.openPick()
      }
    }
  }

  Item {
    visible: root.mode === "pick"
    anchors.fill: parent

    TextField {
      id: searchLine
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      placeholderText: "Search feeds, or paste a site or feed address…"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: root.searchText = text
      onAccepted: if (root.pickCount > 0) root.pickAt(root.selectedIndex)
    }

    Text {
      id: pickStatus
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchLine.bottom
      anchors.topMargin: Style.spacing.sm
      visible: text.length > 0
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.probing ? "Looking for a feed at " + root.searchText.trim() + "…" : (root.probeError || (root.catalog.length === 0 ? "Loading…" : (root.pickCount === 0 ? "No matches" : "")))
      color: root.probeError ? Color.urgent : root.foreground
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    ListView {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: pickStatus.visible ? pickStatus.bottom : searchLine.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.pickCount
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (count > 0 && currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: Choice {
        required property int index
        readonly property bool urlRow: root.offerUrl && index === 0
        readonly property var match: urlRow ? null : (root.matches[index - (root.offerUrl ? 1 : 0)] || ({}))
        width: ListView.view.width
        selected: index === root.selectedIndex
        title: urlRow ? "Add " + root.searchText.trim() : String(match.name || "")
        note: urlRow ? "A feed, or a page that links to one" : (match.added ? "Already on the tile" : String(match.url || ""))
        dim: !urlRow && !!match.added
        onHovered: root.selectedIndex = index
        onPicked: root.pickAt(index)
      }
    }
  }
}
