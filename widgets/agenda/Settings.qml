import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/kit.js" as Kit

// The calendars on the tile. An address like Google's secret iCal link is a
// password, so agenda.py keeps the list in its own private file: this panel
// never stores one in the launcher's settings, and hands a new one over in the
// environment rather than on a command line.
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

  property var calendars: []
  property bool loaded: false
  property bool adding: false
  property string message: ""
  property bool failed: false
  property int selectedIndex: -1

  readonly property int maxCalendars: 8
  readonly property string script: Kit.localPath(Qt.resolvedUrl("agenda.py"))

  implicitWidth: Style.space(420)
  implicitHeight: column.implicitHeight + Style.space(8)

  function reload() {
    lister.running = true
  }

  function add() {
    var source = String(urlField.text || "").trim()
    if (!source || adder.running) return
    root.adding = true
    root.failed = false
    root.message = "Checking the calendar…"
    adder.environment = { "ANDE_CALENDAR_URL": source, "ANDE_CALENDAR_NAME": String(nameField.text || "").trim() }
    adder.command = ["/usr/bin/python3", root.script, "--add"]
    adder.running = true
  }

  function remove(id) {
    if (!id || remover.running) return
    remover.command = ["/usr/bin/python3", root.script, "--remove", String(id)]
    remover.running = true
  }

  function handleEscape() {
    if (urlField.activeFocus || nameField.activeFocus) {
      root.forceActiveFocus()
      return true
    }
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.calendars.length
    if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && count > 0) {
      var step = event.key === Qt.Key_Down ? 1 : -1
      root.selectedIndex = root.selectedIndex < 0 ? (step > 0 ? 0 : count - 1) : (root.selectedIndex + step + count) % count
      return true
    }
    if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.selectedIndex >= 0 && root.selectedIndex < count) {
      root.remove(root.calendars[root.selectedIndex].id)
      return true
    }
    return false
  }

  Component.onCompleted: {
    root.reload()
    root.forceActiveFocus()
  }

  Process {
    id: lister
    command: ["/usr/bin/python3", root.script, "--list"]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: {
      var data = null
      try { data = JSON.parse(listOut.text || "") } catch (e) { data = null }
      root.calendars = data && Array.isArray(data.calendars) ? data.calendars : []
      root.loaded = true
      if (root.selectedIndex >= root.calendars.length) root.selectedIndex = root.calendars.length - 1
    }
  }

  Process {
    id: adder
    stdout: StdioCollector { id: addOut; waitForEnd: true }
    onExited: {
      root.adding = false
      var data = null
      try { data = JSON.parse(addOut.text || "") } catch (e) { data = null }
      if (!data || data.ok !== true) {
        root.failed = true
        root.message = data && data.error ? String(data.error) : "That calendar could not be read"
        return
      }
      root.failed = false
      var count = Number(data.events) || 0
      root.message = "Added " + data.calendar.name + " · " + count + (count === 1 ? " event" : " events")
      urlField.text = ""
      nameField.text = ""
      root.reload()
      root.forceActiveFocus()
    }
  }

  Process {
    id: remover
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      root.message = ""
      root.reload()
    }
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(8)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: !root.loaded ? "Loading…" : (root.calendars.length === 0 ? "No calendars yet" : "On the tile")
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.calendars

      BorderSurface {
        id: calendarRow
        required property var modelData
        required property int index
        width: column.width
        height: Style.space(44)
        radius: root.cornerRadius
        color: index === root.selectedIndex ? root.hoverFill : "transparent"
        borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: root.selectedIndex = calendarRow.index
        }

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.right: drop.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(calendarRow.modelData.name || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(calendarRow.modelData.where || "")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }

        IconButton {
          id: drop
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰅖"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.remove(calendarRow.modelData.id)
        }
      }
    }

    Item { width: 1; height: Style.space(4) }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.calendars.length >= root.maxCalendars ? "Up to " + root.maxCalendars + " calendars" : "Add a calendar"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: urlField
      visible: root.calendars.length < root.maxCalendars
      width: parent.width
      placeholderText: "Paste an iCal or webcal address, or an .ics file path"
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.add()
    }

    Row {
      visible: urlField.visible
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: nameField
        width: parent.width - addButton.width - parent.spacing
        placeholderText: "Name (optional)"
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: root.add()
      }

      IconButton {
        id: addButton
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(30)
        glyph: "󰐕"
        label: "Add"
        filled: true
        busy: root.adding
        available: String(urlField.text || "").trim().length > 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.add()
      }
    }

    Text {
      visible: root.message.length > 0
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.message
      color: root.failed ? Color.urgent : root.foreground
      opacity: root.failed ? 1 : 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Google: calendar settings → Integrate calendar → Secret address in iCal format.\n"
        + "iCloud: share the calendar as Public and copy its webcal link.\n"
        + "Outlook: Settings → Calendar → Shared calendars → Publish → ICS link.\n"
        + "Fastmail, Proton, and most others: look for an ICS or iCal subscription link.\n"
        + "A local .ics file, or a folder of them (vdirsyncer), works too."
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      lineHeight: 1.15
    }
  }
}
