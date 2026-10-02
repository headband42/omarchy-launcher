import QtQuick
import qs.Commons
import "../_kit"
import "github.js" as GitHub

// Pull requests that ask for your review and the ones you opened, with their
// checks and review state. Everything is read through the gh CLI.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowSec: Date.now() / 1000

  readonly property var rows: GitHub.rows(root.sample)
  readonly property int waiting: GitHub.waitingCount(root.sample)
  readonly property string unread: GitHub.notificationsLabel(root.sample)

  function open(url) {
    if (url && root.host && root.host.openLink) root.host.openLink(String(url))
  }

  function toneColor(tone) {
    if (tone === "failure") return Color.urgent
    if (tone === "success") return Color.accent
    return root.foreground
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("github.py")
    interval: 180000
    active: root.visible
    onSampled: function(data) { if (data && data.ok === true) root.sample = data }
  }

  Timer {
    interval: 60000
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
      width: parent.width - (bell.visible ? bell.width + Style.space(4) : 0)
      title: "GITHUB"
      trailing: root.sample && root.sample.login ? root.sample.login : ""
      dotColor: root.waiting > 0 ? Color.accent : root.foreground
      dotOpacity: root.waiting > 0 ? 1 : 0.35
      pulse: root.waiting > 0
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // Unread notifications. A click opens them on github.com.
    Item {
      id: bell
      visible: root.unread.length > 0
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      width: bellRow.implicitWidth + Style.space(12)
      height: Style.space(20)

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Color.accent
        opacity: bellMouse.containsMouse ? 0.35 : 0.2
      }

      Row {
        id: bellRow
        anchors.centerIn: parent
        spacing: Style.space(3)

        Text {
          textFormat: Text.PlainText
          text: "󰂚"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          text: root.unread
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
      }

      MouseArea {
        id: bellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.open("https://github.com/notifications")
      }
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
        readonly property bool isHeader: modelData.kind === "header"
        readonly property var pr: modelData.pr || ({})
        readonly property string tone: isHeader ? "" : GitHub.tone(pr, modelData.mine)
        readonly property string noteText: isHeader ? "" : GitHub.note(pr)
        width: ListView.view.width
        height: isHeader ? Style.space(index === 0 ? 16 : 22) : Style.space(36)

        Text {
          visible: row.isHeader
          anchors.left: parent.left
          anchors.leftMargin: Style.space(2)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(2)
          textFormat: Text.PlainText
          text: row.isHeader ? row.modelData.label + " · " + row.modelData.count : ""
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 0.5
        }

        Rectangle {
          visible: !row.isHeader
          anchors.fill: parent
          radius: Style.space(5)
          color: root.foreground
          opacity: rowMouse.containsMouse ? 0.07 : 0
        }

        Text {
          id: glyph
          visible: !row.isHeader
          anchors.left: parent.left
          anchors.leftMargin: Style.space(3)
          y: Style.space(3)
          width: Style.space(16)
          textFormat: Text.PlainText
          text: GitHub.checkGlyph(row.pr)
          color: row.pr.checks === "failure" ? Color.urgent : (row.pr.checks === "success" ? Color.accent : root.foreground)
          opacity: row.pr.checks ? 1 : 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: title
          visible: !row.isHeader
          anchors.left: glyph.right
          anchors.leftMargin: Style.space(3)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(3)
          y: Style.space(2)
          textFormat: Text.PlainText
          text: row.isHeader ? "" : "#" + row.pr.number + " " + row.pr.title
          color: root.foreground
          opacity: row.pr.draft ? 0.55 : 1
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          visible: !row.isHeader
          anchors.left: title.left
          anchors.right: parent.right
          anchors.rightMargin: Style.space(3)
          anchors.top: title.bottom
          anchors.topMargin: Style.space(1)
          textFormat: Text.PlainText
          text: row.noteText.length > 0 ? row.noteText + " · " + GitHub.caption(row.pr, root.nowSec, row.modelData.mine)
            : GitHub.caption(row.pr, root.nowSec, row.modelData.mine)
          color: root.toneColor(row.tone)
          opacity: row.tone ? 0.95 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        MouseArea {
          id: rowMouse
          visible: !row.isHeader
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.open(row.pr.url)
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
        text: root.sample && root.sample.state === "ok" ? "󰄬" : "󰊤"
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
        text: GitHub.emptyText(root.sample)
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
