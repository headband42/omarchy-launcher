import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../_kit"
import "../_kit/kit.js" as Kit
import "mail.js" as Mail

// The mail accounts on the tile. An app password is a password, so mail.py
// keeps the list in its own private file: this panel never stores one in the
// launcher's settings, and hands a new one over in the environment rather
// than on a command line. An account is saved only once it signs in.
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

  property var accounts: []
  property int maxAccounts: 4
  property bool loaded: false
  property bool adding: false
  property string message: ""
  property bool failed: false
  property int selectedIndex: -1

  readonly property string script: Kit.localPath(Qt.resolvedUrl("mail.py"))
  readonly property bool full: root.accounts.length >= root.maxAccounts

  implicitWidth: Style.space(440)
  implicitHeight: column.implicitHeight + Style.space(8)

  function reload() {
    lister.running = true
  }

  function add() {
    var address = String(addressField.text || "").trim()
    var password = String(passwordField.text || "")
    if (!address || !password.trim() || adder.running) return
    root.adding = true
    root.failed = false
    root.message = "Signing in…"
    adder.environment = {
      "ANDE_MAIL_ADDRESS": address,
      "ANDE_MAIL_PASSWORD": password,
      "ANDE_MAIL_SERVER": String(serverField.text || "").trim()
    }
    adder.command = ["/usr/bin/python3", root.script, "--add"]
    adder.running = true
  }

  function remove(id) {
    if (!id || changer.running) return
    changer.command = ["/usr/bin/python3", root.script, "--remove", String(id)]
    changer.running = true
  }

  function cycleView(account) {
    if (!account || !account.gmail || changer.running) return
    changer.command = ["/usr/bin/python3", root.script, "--view", String(account.id), Mail.nextView(account.view)]
    changer.running = true
  }

  function handleEscape() {
    if (addressField.activeFocus || passwordField.activeFocus || serverField.activeFocus) {
      root.forceActiveFocus()
      return true
    }
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.accounts.length
    if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && count > 0) {
      var step = event.key === Qt.Key_Down ? 1 : -1
      root.selectedIndex = root.selectedIndex < 0 ? (step > 0 ? 0 : count - 1) : (root.selectedIndex + step + count) % count
      return true
    }
    if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.selectedIndex >= 0 && root.selectedIndex < count) {
      root.remove(root.accounts[root.selectedIndex].id)
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
        && root.selectedIndex >= 0 && root.selectedIndex < count) {
      root.cycleView(root.accounts[root.selectedIndex])
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
      root.accounts = data && Array.isArray(data.accounts) ? data.accounts : []
      if (data && Number(data.max) > 0) root.maxAccounts = Number(data.max)
      root.loaded = true
      if (root.selectedIndex >= root.accounts.length) root.selectedIndex = root.accounts.length - 1
    }
  }

  Process {
    id: adder
    stdout: StdioCollector { id: addOut; waitForEnd: true }
    onExited: {
      root.adding = false
      // The password leaves the environment as soon as the check is done.
      adder.environment = ({})
      var data = null
      try { data = JSON.parse(addOut.text || "") } catch (e) { data = null }
      if (!data || data.ok !== true) {
        root.failed = true
        root.message = data && data.error ? String(data.error) : "That account could not be read"
        return
      }
      root.failed = false
      var count = Number(data.unread) || 0
      root.message = "Added " + data.account.address + " · " + (count > 0 ? count + " unread" : "nothing unread")
      addressField.text = ""
      passwordField.text = ""
      serverField.text = ""
      root.reload()
      root.forceActiveFocus()
    }
  }

  Process {
    id: changer
    stdout: StdioCollector { id: changeOut; waitForEnd: true }
    onExited: {
      var data = null
      try { data = JSON.parse(changeOut.text || "") } catch (e) { data = null }
      root.failed = !!(data && data.ok === false && data.error)
      root.message = root.failed ? String(data.error) : ""
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
      text: !root.loaded ? "Loading…" : (root.accounts.length === 0 ? "No accounts yet" : "On the tile")
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.accounts

      BorderSurface {
        id: accountRow
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
          onEntered: root.selectedIndex = accountRow.index
        }

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.right: viewPill.visible ? viewPill.left : drop.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(accountRow.modelData.address || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(accountRow.modelData.providerName || "Mail") + " · " + String(accountRow.modelData.where || "")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }

        // Gmail only: count the Primary tab, the whole inbox, or Important.
        IconButton {
          id: viewPill
          visible: !!accountRow.modelData.gmail
          anchors.right: drop.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          label: Mail.viewLabel(accountRow.modelData.view)
          filled: true
          busy: changer.running
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.cycleView(accountRow.modelData)
        }

        IconButton {
          id: drop
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰅖"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.remove(accountRow.modelData.id)
        }
      }
    }

    Item { width: 1; height: Style.space(4) }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.full ? "Up to " + root.maxAccounts + " accounts" : "Add an account"
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: addressField
      visible: !root.full
      width: parent.width
      placeholderText: "Email address"
      inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: passwordField.forceActiveFocus()
    }

    TextField {
      id: passwordField
      visible: !root.full
      width: parent.width
      password: true
      placeholderText: "App password"
      inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onAccepted: root.add()
    }

    Row {
      visible: !root.full
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: serverField
        width: parent.width - addButton.width - parent.spacing
        placeholderText: "IMAP server (only if it isn't found)"
        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
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
        available: String(addressField.text || "").trim().length > 0 && String(passwordField.text || "").trim().length > 0
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
      text: "Gmail and Google Workspace: turn on 2-Step Verification, then make an app password at myaccount.google.com/apppasswords.\n"
        + "iCloud: account.apple.com → Sign-In and Security → App-Specific Passwords.\n"
        + "Yahoo and AOL: Account security → Generate app password. Fastmail: Settings → Privacy & Security → App passwords.\n"
        + "Proton: run Proton Mail Bridge and paste the password it shows.\n"
        + "Others: the server is found from the address; type it only when asked.\n"
        + "Outlook and Hotmail take only a Microsoft sign-in, which the tile can't do."
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      lineHeight: 1.15
    }
  }
}
