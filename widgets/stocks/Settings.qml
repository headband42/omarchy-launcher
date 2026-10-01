import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/kit.js" as Kit
import "stocks.js" as Stocks

// The tickers the tile shows, top first. With none picked, the tile follows
// Omafinance's watchlist. Typing anywhere starts a search.
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
  // Company names by symbol, from the quote probe and from search picks.
  property var names: ({})
  property var watchlist: []

  readonly property string panelTitle: root.mode === "pick" ? "Add ticker" : ""
  readonly property int contentWidth: Style.space(380)
  readonly property var symbols: Stocks.normalizeSymbols(root.settings)
  readonly property bool full: root.symbols.length >= Stocks.maxSymbols()
  readonly property int homeCount: root.symbols.length + (root.full ? 0 : 1)
  readonly property string introText: {
    if (root.symbols.length === 0) {
      if (root.watchlist.length > 0)
        return "Following your Omafinance watchlist: " + root.watchlist.join(", ")
          + ". Add tickers to show a different list."
      return "Showing the S&P 500, Nasdaq, Dow, and Bitcoin. Add tickers to show your own."
    }
    var text = "Up to " + Stocks.maxSymbols() + ", top first. A short tile shows as many as fit."
    if (root.watchlist.length > 0) text += " Remove them all to follow your Omafinance watchlist again."
    return text
  }

  implicitWidth: root.contentWidth
  implicitHeight: root.mode === "pick" ? Style.space(430) : home.implicitHeight

  function commit(list) {
    // The settings host stores this for the widget. An empty object forgets it.
    root.settings = Stocks.settingsFromSymbols(list) || ({})
  }

  function rememberNames(list) {
    var next = {}
    for (var key in root.names) next[key] = root.names[key]
    var items = Stocks.toList(list)
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (item && item.symbol && item.name && item.missing !== true) next[String(item.symbol)] = String(item.name)
    }
    root.names = next
  }

  function addSymbol(row) {
    var symbol = Stocks.normalizeSymbol(row && row.symbol)
    if (!symbol || root.full || root.symbols.indexOf(symbol) >= 0) return
    root.rememberNames([row])
    root.commit(root.symbols.concat([symbol]))
    root.mode = "home"
    root.searchText = ""
    root.rows = []
    root.searchLoaded = false
    root.selectedIndex = root.symbols.indexOf(symbol)
    root.forceActiveFocus()
  }

  function removeAt(index) {
    if (index < 0 || index >= root.symbols.length) return
    var next = root.symbols.slice()
    next.splice(index, 1)
    root.commit(next)
    var count = next.length + 1
    if (root.selectedIndex >= count) root.selectedIndex = Math.max(0, count - 1)
  }

  function openPick() {
    if (root.full) return
    root.mode = "pick"
    root.searchText = ""
    root.rows = []
    root.searchLoaded = false
    root.searchFailed = false
    root.selectedIndex = 0
    root.forceActiveFocus()
  }

  function beginSearch() {
    var query = root.searchText.trim()
    if (!query) {
      root.rows = []
      root.searchLoaded = false
      root.searchFailed = false
      return
    }
    if (searchProbe.running) {
      searchProbe.again = true
      return
    }
    searchProbe.query = query
    searchProbe.command = ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("stocks.py")), "--search", query]
    searchProbe.running = true
  }

  function isTyping(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
      && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
  }

  function handleEscape() {
    if (root.mode !== "pick") return false
    if (root.searchText) {
      root.searchText = ""
      return true
    }
    root.mode = "home"
    root.selectedIndex = root.symbols.length
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
        if (root.selectedIndex >= root.symbols.length) root.openPick()
        return true
      }
      if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
        root.removeAt(root.selectedIndex)
        return true
      }
      if (root.isTyping(event) && !root.full) {
        root.openPick()
        root.searchText = event.text
        return true
      }
      return false
    }
    var listed = root.rows.length
    if (event.key === Qt.Key_Up && listed > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + listed) % listed
      return true
    }
    if (event.key === Qt.Key_Down && listed > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % listed
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && listed > 0) {
      root.addSymbol(root.rows[root.selectedIndex])
      return true
    }
    if (event.key === Qt.Key_Backspace) {
      root.searchText = root.searchText.slice(0, -1)
      return true
    }
    if (root.isTyping(event)) {
      root.searchText += event.text
      return true
    }
    return false
  }

  // Names for the picked tickers. stocks.py answers with the quotes.
  Poller {
    script: Qt.resolvedUrl("stocks.py")
    args: ["--symbols", root.symbols.join(",")]
    interval: 0
    active: root.symbols.length > 0
    onSampled: function(data) { if (data && data.ok === true) root.rememberNames(data.quotes) }
  }

  // The list the tile follows when none are picked.
  FileView {
    path: String(Quickshell.env("HOME") || "") + "/.local/state/omarchy/settings/finance.json"
    printErrors: false
    watchChanges: false
    onLoaded: root.watchlist = Stocks.parseWatchlist(text())
  }

  Process {
    id: searchProbe
    property bool again: false
    property string query: ""
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: {
      // The text changed while this ran. Its answer is for an old query.
      if (searchProbe.again || searchProbe.query !== root.searchText.trim()) {
        searchProbe.again = false
        Qt.callLater(root.beginSearch)
        return
      }
      var parsed = null
      try { parsed = JSON.parse(searchOut.text || "") } catch (e) { parsed = null }
      root.searchFailed = !Array.isArray(parsed)
      root.rows = root.searchFailed ? [] : parsed
      root.searchLoaded = true
    }
  }

  Timer {
    id: searchDelay
    interval: 280
    onTriggered: root.beginSearch()
  }

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
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.introText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.symbols

        BorderSurface {
          required property int index
          required property var modelData
          width: parent.width
          height: Style.space(50)
          radius: root.cornerRadius
          color: index === root.selectedIndex ? root.hoverFill : "transparent"
          borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.selectedIndex = index
            onClicked: root.selectedIndex = index
          }

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
              text: String(modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(root.names[String(modelData)] || "")
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
              onClicked: root.removeAt(index)
            }
          }
        }
      }

      BorderSurface {
        visible: !root.full
        width: parent.width
        height: Style.space(50)
        radius: root.cornerRadius
        color: root.selectedIndex === root.symbols.length ? root.hoverFill : "transparent"
        borderSpec: root.selectedIndex === root.symbols.length ? root.borderSpec : Border.none()

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
            text: "Add ticker"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.symbols.length + " of " + Stocks.maxSymbols() + " · or just start typing"
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
          onEntered: root.selectedIndex = root.symbols.length
          onClicked: root.openPick()
        }
      }
    }

    Text {
      visible: root.full
      width: parent.width
      textFormat: Text.PlainText
      text: Stocks.maxSymbols() + " of " + Stocks.maxSymbols()
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
      id: searchLine
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      textFormat: Text.PlainText
      text: root.searchText.length > 0 ? root.searchText : "Search tickers…"
      color: root.foreground
      opacity: root.searchText.length > 0 ? 1 : 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    Text {
      id: searchStatus
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchLine.bottom
      anchors.topMargin: Style.spacing.md
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      visible: text.length > 0
      text: {
        if (root.searchText.trim().length === 0) return "Type a symbol or a company name."
        if (root.searchFailed) return "Search failed. Yahoo Finance did not answer."
        if (!root.searchLoaded) return "Searching…"
        if (root.rows.length === 0) return "No matches"
        return ""
      }
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    ListView {
      id: pickList
      visible: root.rows.length > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: searchLine.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      clip: true
      spacing: Style.spacing.xs
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows.length
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (count > 0 && currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: BorderSurface {
        required property int index
        readonly property var match: root.rows[index] || ({})
        readonly property bool added: root.symbols.indexOf(String(match.symbol || "")) >= 0
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
            text: String(match.symbol || "") + "  " + String(match.name || "")
            color: root.foreground
            opacity: added ? 0.5 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: added ? "Already on the tile"
              : [String(match.type || ""), String(match.exchange || "")].filter(function(part) { return part.length > 0 }).join(" · ")
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
          cursorShape: added ? Qt.ArrowCursor : Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: root.addSymbol(match)
        }
      }
    }
  }
}
