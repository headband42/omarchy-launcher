import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit/kit.js" as Kit
import "repo.js" as Repo

// Which repository the tile watches: type a path, or pick one of the git
// work trees found under the home folder (most recently used first).
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

  property var found: []
  property bool searched: false
  property int selectedIndex: -1
  property real now: Date.now() / 1000

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string current: String((root.settings && root.settings.path) || "")

  implicitWidth: Style.space(380)
  implicitHeight: Style.space(360)

  function commit(path) {
    root.settings = Repo.settingsFromPath(path)
    pathField.text = root.current
    root.forceActiveFocus()
  }

  function same(a, b) {
    var x = Repo.displayPath(String(a || ""), root.home).replace(/\/+$/, "")
    var y = Repo.displayPath(String(b || ""), root.home).replace(/\/+$/, "")
    return x === y
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.found.length
    if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && count > 0) {
      var step = event.key === Qt.Key_Down ? 1 : -1
      root.selectedIndex = root.selectedIndex < 0 ? (step > 0 ? 0 : count - 1)
        : (root.selectedIndex + step + count) % count
      root.forceActiveFocus()
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selectedIndex >= 0 && root.selectedIndex < count) {
      root.commit(root.found[root.selectedIndex].path)
      return true
    }
    return false
  }

  Process {
    id: finder
    command: ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("repo.py")), "--find"]
    stdout: StdioCollector { id: findOut; waitForEnd: true }
    onExited: {
      var rows = []
      try {
        var parsed = JSON.parse(findOut.text || "{}")
        rows = Repo.toList(parsed && parsed.repos)
      } catch (e) { rows = [] }
      root.found = rows
      root.searched = true
    }
  }

  Component.onCompleted: finder.running = true

  Column {
    id: top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(8)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Repository to watch"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    TextField {
      id: pathField
      width: parent.width
      text: root.current
      placeholderText: "Empty watches your home folder"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onEditingFinished: if (String(text || "").trim() !== root.current) root.commit(text)
      onAccepted: root.commit(text)
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: !root.searched ? "Looking for repositories…"
        : (root.found.length > 0 ? "Found in your home folder" : "No repositories found in your home folder")
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.topMargin: Style.space(6)
    anchors.bottom: hint.top
    anchors.bottomMargin: Style.space(8)
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds
    model: root.found.length
    currentIndex: root.selectedIndex
    onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)

    delegate: BorderSurface {
      id: row
      required property int index
      readonly property var repo: root.found[index] || ({})
      readonly property bool chosen: root.same(row.repo.path, root.current)
      width: ListView.view.width
      height: Style.space(46)
      radius: root.cornerRadius
      color: index === root.selectedIndex ? root.hoverFill : "transparent"
      borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

      Text {
        id: mark
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        textFormat: Text.PlainText
        text: row.chosen ? "" : ""
        color: row.chosen ? Color.accent : root.foreground
        opacity: row.chosen ? 1 : 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Column {
        anchors.left: mark.right
        anchors.leftMargin: Style.space(8)
        anchors.right: age.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(row.repo.name || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: row.chosen ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(row.repo.path || "")
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      Text {
        id: age
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Repo.ageLabel(row.repo.at, root.now)
        color: root.foreground
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.selectedIndex = row.index
        onClicked: root.commit(row.repo.path)
      }
    }
  }

  Text {
    id: hint
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: "A click on the tile opens lazygit there. The footer opens a terminal or the folder, and fetches."
    color: root.foreground
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
