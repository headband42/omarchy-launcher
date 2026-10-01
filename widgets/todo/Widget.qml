import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "todo.js" as Todo

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var rows: []
  property string draft: ""
  property bool adding: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string todoPath: Todo.resolvePath(root.tile && root.tile.settings ? root.tile.settings.path : "", root.home)
  readonly property bool showDone: !!(root.tile && root.tile.settings && root.tile.settings.showDone)
  readonly property var shown: Todo.visible(root.rows, root.showDone)
  readonly property int openCount: {
    var n = 0
    for (var i = 0; i < root.rows.length; i++) if (!root.rows[i].done) n++
    return n
  }

  function save() {
    todoFile.setText(Todo.format(root.rows))
  }

  function toggleAt(index) {
    root.rows = Todo.toggle(root.rows, index)
    root.save()
  }

  function removeAt(index) {
    root.rows = Todo.remove(root.rows, index)
    root.save()
  }

  function beginAdd() {
    root.adding = true
    entry.forceActiveFocus()
  }

  function commitDraft() {
    var next = Todo.add(root.rows, root.draft)
    if (next.length !== root.rows.length) {
      root.rows = next
      root.save()
    }
    root.draft = ""
  }

  function endAdd() {
    root.draft = ""
    root.adding = false
    entry.focus = false
    root.forceActiveFocus()
  }

  Component.onCompleted: {
    var dir = Todo.dirOf(root.todoPath)
    if (dir) Util.execDetached("mkdir -p " + Util.shellQuote(dir))
  }

  FileView {
    id: todoFile
    path: root.todoPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.rows = Todo.parse(text())
    onLoadFailed: root.rows = []
    onPathChanged: reload()
    onFileChanged: reload()
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

    WidgetHeader {
      title: "TODO"
      trailing: String(root.openCount)
      dotColor: root.openCount > 0 ? Color.accent : root.foreground
      dotOpacity: root.openCount > 0 ? 1 : 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Column {
      id: stack
      width: parent.width
      height: parent.height - Style.font.caption - 4 - parent.spacing - (entryRow.height + parent.spacing)
      spacing: Style.space(3)

      Repeater {
        model: root.shown.slice(0, 4)

        Item {
          required property var modelData
          width: stack.width
          height: (stack.height - stack.spacing * Math.max(0, Math.min(4, root.shown.length) - 1)) / Math.max(1, Math.min(4, root.shown.length))

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            height: parent.height
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(10)
              height: width
              radius: Style.space(2)
              y: Math.max(0, (parent.height - height) / 2)
              color: modelData.done ? Color.accent : "transparent"
              border.color: modelData.done ? Color.accent : root.foreground
              border.width: 1
              opacity: modelData.done ? 1 : 0.5
            }

            Text {
              width: parent.width - Style.space(10) - parent.spacing
              y: Math.max(0, (parent.height - height) / 2)
              textFormat: Text.PlainText
              text: String(modelData.text || "")
              color: root.foreground
              opacity: modelData.done ? 0.4 : 0.9
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.strikeout: modelData.done
              elide: Text.ElideRight
            }
          }

          Text {
            id: removeMark
            visible: removeMouse.containsMouse
            width: Style.space(14)
            anchors.right: parent.right
            y: Math.max(0, (parent.height - height) / 2)
            textFormat: Text.PlainText
            text: "×"
            color: root.foreground
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignRight
          }

          MouseArea {
            id: removeMouse
            width: Style.space(16)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeAt(modelData.index)
          }

          MouseArea {
            anchors.left: parent.left
            anchors.right: removeMouse.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleAt(modelData.index)
          }
        }
      }
    }

    Item {
      id: entryRow
      width: parent.width
      height: Style.font.caption + 8

      Text {
        anchors.fill: parent
        visible: !root.adding
        textFormat: Text.PlainText
        text: root.rows.length > 0 ? "＋ add" : "＋ add the first item"
        color: root.foreground
        opacity: addMouse.containsMouse ? 0.9 : 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        anchors.fill: parent
        visible: root.adding
        textFormat: Text.PlainText
        text: root.draft.length > 0 ? root.draft : "type a task…"
        color: root.foreground
        opacity: root.draft.length > 0 ? 0.9 : 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }

      MouseArea {
        id: addMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.beginAdd()
      }

      // Keys go to the widget instead of the menu filter while adding.
      Item {
        id: entry
        focus: false

        onActiveFocusChanged: {
          if (root.host && root.host.setEntryActive) root.host.setEntryActive(entry.activeFocus)
        }

        Keys.onPressed: function(event) {
          if (!entry.activeFocus) return
          if (event.key === Qt.Key_Escape) {
            root.endAdd()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commitDraft()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Backspace) {
            root.draft = root.draft.slice(0, -1)
            event.accepted = true
            return
          }
          var cleanMods = event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier)
          if (cleanMods !== Qt.NoModifier) return
          var text = event.text || ""
          if (text.length === 1 && text.charCodeAt(0) >= 32) {
            root.draft += text
            event.accepted = true
          }
        }
      }
    }
  }
}
