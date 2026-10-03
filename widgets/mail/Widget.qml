import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "../_kit/kit.js" as Kit
import "mail.js" as Mail

// Unread mail, newest first, from every account the gear added. A row opens
// its conversation in Gmail, or the account's webmail; hover one to mark it
// read. The last reply is drawn from the cache while the first poll of a
// session is out. Empty chrome falls through to the slot's Opens.
Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  // A reply from mail.py this session, not the cache.
  property bool live: false
  // Messages marked read here, by "account:uid", until a poll catches up.
  property var hidden: ({})
  property var readQueue: []
  property double nowSec: Date.now() / 1000

  readonly property string script: Kit.localPath(Qt.resolvedUrl("mail.py"))
  readonly property var rows: Mail.rows(root.sample, root.hidden)
  readonly property int unread: Mail.totalUnread(root.sample, root.hidden)
  readonly property string cachePath: {
    var base = String(Quickshell.env("XDG_CACHE_HOME") || "")
    if (!base) base = String(Quickshell.env("HOME") || "") + "/.cache"
    return base + "/ande.launcher/mail.json"
  }

  function apply(data) {
    root.nowSec = Date.now() / 1000
    if (!data || data.ok !== true) return
    root.sample = data
    root.live = true
    if (!reader.running && root.readQueue.length === 0) root.hidden = ({})
  }

  function open(row) {
    var url = Mail.target(row)
    if (url && root.host && root.host.openLink) root.host.openLink(url)
    else if (root.host && root.host.launchDefault) root.host.launchDefault()
  }

  function markRead(row) {
    if (!row || !row.canRead) return
    var key = Mail.hiddenKey(row.account, row.message.uid)
    if (root.hidden[key]) return
    var next = Object.assign({}, root.hidden)
    next[key] = true
    root.hidden = next
    root.readQueue = root.readQueue.concat([[row.account, String(row.uidvalidity), String(row.message.uid)]])
    root.nextRead()
  }

  function nextRead() {
    if (reader.running || root.readQueue.length === 0) return
    var args = root.readQueue[0]
    root.readQueue = root.readQueue.slice(1)
    reader.command = ["/usr/bin/python3", root.script, "--read"].concat(args)
    reader.running = true
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("mail.py")
    interval: 60000
    active: root.visible
    onSampled: function(data) { root.apply(data) }
  }

  FileView {
    path: root.cachePath
    printErrors: false
    watchChanges: false
    onLoaded: {
      if (root.live) return
      var cached = Mail.fromCache(text())
      if (cached) root.sample = cached
    }
  }

  // One message at a time; the poll after the last one shows the truth.
  Process {
    id: reader
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.readQueue.length > 0) Qt.callLater(root.nextRead)
      else poller.pollSoon()
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.visible
    onTriggered: root.nowSec = Date.now() / 1000
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: Mail.title(root.sample)
      trailing: Mail.unreadLabel(root.unread)
      dotColor: root.unread > 0 ? Color.accent : root.foreground
      dotOpacity: root.unread > 0 ? 1 : 0.35
      pulse: Mail.fresh(root.sample, root.hidden, root.nowSec)
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    ListView {
      id: list
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: parent.bottom
      width: parent.width
      clip: true
      spacing: Style.space(1)
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.rows

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property string kind: modelData.kind
        readonly property var message: modelData.message || ({})
        readonly property bool hot: rowMouse.containsMouse || readButton.hovered
        width: ListView.view.width
        height: row.kind === "message" ? Style.space(36)
          : (row.kind === "account" ? Style.space(index === 0 ? 16 : 22) : Style.space(20))

        Rectangle {
          visible: row.kind !== "account"
          anchors.fill: parent
          radius: Style.space(5)
          color: root.foreground
          opacity: row.hot ? 0.07 : 0
        }

        // An account's name and count, or what is wrong with it.
        Text {
          visible: row.kind === "account"
          anchors.left: parent.left
          anchors.leftMargin: Style.space(2)
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(2)
          textFormat: Text.PlainText
          text: row.kind !== "account" ? ""
            : row.modelData.label + " · " + (row.modelData.error || (row.modelData.count > 0 ? row.modelData.count : "all read"))
          color: row.modelData.error ? Color.urgent : root.foreground
          opacity: row.modelData.error ? 0.95 : 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 0.5
          elide: Text.ElideRight
        }

        Text {
          visible: row.kind === "more"
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.kind === "more" ? "+ " + row.modelData.count + " more unread" : ""
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: star
          visible: row.kind === "message" && !!row.message.flagged
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          y: Style.space(3)
          width: visible ? implicitWidth + Style.space(3) : 0
          textFormat: Text.PlainText
          text: "󰓎"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: sender
          visible: row.kind === "message"
          anchors.left: star.right
          anchors.right: age.left
          anchors.rightMargin: Style.space(6)
          y: Style.space(2)
          textFormat: Text.PlainText
          text: String(row.message.from || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          id: age
          visible: row.kind === "message" && !(row.hot && row.modelData.canRead)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.baseline: sender.baseline
          textFormat: Text.PlainText
          text: Mail.fmtAge(root.nowSec, row.message.date)
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: row.kind === "message"
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.right: parent.right
          anchors.rightMargin: row.hot && row.modelData.canRead ? readButton.width + Style.space(6) : Style.space(4)
          anchors.top: sender.bottom
          anchors.topMargin: Style.space(1)
          textFormat: Text.PlainText
          text: String(row.message.subject || "")
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        MouseArea {
          id: rowMouse
          visible: row.kind !== "account" || row.modelData.web.length > 0
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.open(row.modelData)
        }

        IconButton {
          id: readButton
          visible: row.kind === "message" && row.modelData.canRead && row.hot
          anchors.right: parent.right
          anchors.rightMargin: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰄬"
          glyphSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.markRead(row.modelData)
        }
      }
    }

    Column {
      visible: root.rows.length === 0
      anchors.centerIn: list
      width: list.width
      spacing: Style.space(6)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Mail.emptyGlyph(root.sample)
        color: root.foreground
        opacity: 0.35
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2)
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: Mail.emptyText(root.sample)
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
