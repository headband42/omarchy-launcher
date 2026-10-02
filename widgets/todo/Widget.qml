import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "todo.js" as Todo

// A checklist kept in a text file, plain or Markdown. Click a task to tick
// it; hover for edit and remove. The footer adds tasks and clears finished
// ones. In Markdown, lines that are not tasks are written back as they were.
Item {
  id: root
  clip: true
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var lines: []
  // Ticked a moment ago: still drawn, struck through, until the timer.
  property var linger: ({})
  // The footer field: closed, adding, or editing the task on line editIndex.
  property bool entryOpen: false
  property int editIndex: -1

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string todoPath: Todo.resolvePath(root.tile && root.tile.settings ? root.tile.settings.path : "", root.home)
  readonly property bool markdown: Todo.isMarkdown(root.todoPath)
  readonly property bool showDone: !!(root.tile && root.tile.settings && root.tile.settings.showDone)
  readonly property var shown: Todo.visible(root.lines, root.showDone, root.linger)
  readonly property var tally: Todo.counts(root.lines)

  function save(next) {
    root.lines = next
    todoFile.setText(Todo.format(next))
  }

  function toggleAt(index) {
    var wasDone = !!(root.lines[index] && root.lines[index].done)
    if (!wasDone && !root.showDone) {
      var keep = {}
      for (var key in root.linger) keep[key] = true
      keep[index] = true
      root.linger = keep
      lingerTimer.restart()
    }
    root.save(Todo.toggle(root.lines, index))
  }

  function removeAt(index) {
    if (root.editIndex === index) root.closeEntry()
    root.linger = ({})
    root.save(Todo.remove(root.lines, index))
  }

  function clearDone() {
    root.linger = ({})
    if (root.editIndex >= 0) root.closeEntry()
    root.save(Todo.clearDone(root.lines))
  }

  function openEntry(index) {
    root.editIndex = index
    root.entryOpen = true
    entry.text = index >= 0 && root.lines[index] ? String(root.lines[index].text || "") : ""
    entry.forceActiveFocus()
    entry.selectAll()
  }

  function commitEntry() {
    var text = String(entry.text || "").trim()
    if (root.editIndex >= 0) {
      if (text) root.save(Todo.rename(root.lines, root.editIndex, text))
      root.closeEntry()
      return
    }
    if (!text) {
      root.closeEntry()
      return
    }
    root.linger = ({})
    root.save(Todo.add(root.lines, text, root.markdown))
    // Stay open for the next one.
    entry.text = ""
    list.positionViewAtBeginning()
  }

  function closeEntry() {
    root.entryOpen = false
    root.editIndex = -1
    entry.text = ""
    if (entry.activeFocus) root.forceActiveFocus()
  }

  Component.onCompleted: {
    var dir = Todo.dirOf(root.todoPath)
    if (dir) Util.execDetached("mkdir -p " + Util.shellQuote(dir))
  }

  Timer {
    id: lingerTimer
    interval: 900
    onTriggered: root.linger = ({})
  }

  FileView {
    id: todoFile
    path: root.todoPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.lines = Todo.parse(text(), root.markdown)
    onLoadFailed: root.lines = []
    onPathChanged: reload()
    onFileChanged: reload()
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "TODO"
      trailing: Todo.summary(root.lines)
      dotColor: root.tally.open > 0 ? Color.accent : root.foreground
      dotOpacity: root.tally.open > 0 ? 1 : 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Rectangle {
      id: track
      visible: root.tally.total > 0
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      width: parent.width
      height: Style.space(3)
      radius: height / 2
      color: Util.alpha(root.foreground, 0.1)

      Rectangle {
        width: Math.round(parent.width * Todo.progress(root.lines))
        height: parent.height
        radius: parent.radius
        color: Color.accent

        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
      }
    }

    // Nothing open: a calm empty state instead of a blank list.
    Column {
      visible: root.shown.length === 0
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -Style.space(8)
      width: parent.width
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.tally.total > 0 ? "" : ""
        color: root.tally.total > 0 ? Color.accent : root.foreground
        opacity: root.tally.total > 0 ? 0.8 : 0.25
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge * 2
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.tally.total > 0 ? "All done" : "Nothing to do"
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    ListView {
      id: list
      anchors.top: track.visible ? track.bottom : header.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: -Style.space(4)
      anchors.rightMargin: -Style.space(4)
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(6)
      clip: true
      spacing: Style.space(1)
      boundsBehavior: Flickable.StopAtBounds
      model: root.shown

      delegate: Item {
        id: row
        required property var modelData
        readonly property bool editing: root.editIndex === row.modelData.index
        width: ListView.view.width
        height: Math.max(Style.space(26), rowText.implicitHeight + Style.space(8))

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: row.editing ? Color.accent : root.foreground
          opacity: row.editing ? 0.14 : (rowMouse.containsMouse ? 0.07 : 0)
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleAt(row.modelData.index)
        }

        Rectangle {
          id: box
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4) + row.modelData.depth * Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(14)
          height: width
          radius: Style.space(4)
          color: row.modelData.done ? Color.accent : "transparent"
          border.width: row.modelData.done ? 0 : Math.max(1, Style.space(1.5))
          border.color: Util.alpha(root.foreground, rowMouse.containsMouse ? 0.8 : 0.45)

          Text {
            anchors.centerIn: parent
            visible: row.modelData.done
            textFormat: Text.PlainText
            text: ""
            color: Color.menu.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: rowText
          anchors.left: box.right
          anchors.leftMargin: Style.space(8)
          anchors.right: tools.visible ? tools.left : parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.text
          color: root.foreground
          opacity: row.modelData.done ? 0.4 : 0.92
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.strikeout: row.modelData.done
          elide: Text.ElideRight
        }

        Row {
          id: tools
          visible: rowMouse.containsMouse || editButton.hovered || removeButton.hovered
          anchors.right: parent.right
          anchors.rightMargin: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter

          IconButton {
            id: editButton
            height: Style.space(22)
            glyph: ""
            glyphSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.openEntry(row.modelData.index)
          }

          IconButton {
            id: removeButton
            height: Style.space(22)
            glyph: ""
            glyphSize: Style.font.bodySmall
            tint: Color.urgent
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.removeAt(row.modelData.index)
          }
        }
      }
    }

    Item {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(28)

      IconButton {
        id: addButton
        visible: !root.entryOpen
        anchors.left: parent.left
        anchors.leftMargin: -Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(26)
        glyph: ""
        label: root.tally.total > 0 ? "Add a task" : "Add the first task"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openEntry(-1)
      }

      TextField {
        id: entry
        visible: root.entryOpen
        anchors.left: parent.left
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: clearButton.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        verticalPadding: Style.space(3)
        placeholderText: root.editIndex >= 0 ? "Rename the task" : "Add a task"
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: root.commitEntry()
        Keys.onEscapePressed: function(event) {
          root.closeEntry()
          event.accepted = true
        }
        // Keys stay here instead of filtering the menu while this has focus.
        onActiveFocusChanged: {
          if (root.host && root.host.setEntryActive) root.host.setEntryActive(entry.activeFocus)
          if (!entry.activeFocus && !String(entry.text || "").trim()) {
            root.entryOpen = false
            root.editIndex = -1
          }
        }
      }

      IconButton {
        id: clearButton
        visible: root.tally.done > 0 && !(root.entryOpen && root.editIndex >= 0)
        anchors.right: parent.right
        anchors.rightMargin: -Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(26)
        glyph: ""
        glyphSize: Style.font.bodySmall
        label: "Clear " + root.tally.done
        labelSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.clearDone()
      }
    }
  }
}
