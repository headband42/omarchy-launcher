import QtQuick
import qs.Commons
import "../_kit"
import "feeds.js" as Feeds

// The newest headlines across a few RSS and Atom feeds. A headline opens in
// the default browser; the wheel scrolls when they do not all fit.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowSec: Date.now() / 1000

  readonly property var picked: Feeds.feeds(root.tile && root.tile.settings)
  readonly property var items: root.sample && Array.isArray(root.sample.items) ? root.sample.items : []

  function open(item) {
    var link = String(item && item.link || "")
    if (link && root.host && root.host.openLink) root.host.openLink(link)
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("feeds.py")
    args: ["--feeds", JSON.stringify(root.picked)]
    interval: 300000
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
      title: "FEEDS"
      trailing: Feeds.headerNote(root.sample)
      dotColor: Feeds.failing(root.sample ? root.sample.feeds : []) > 0 ? Color.urgent : Color.accent
      dotOpacity: root.items.length > 0 ? 1 : 0.35
      pulse: root.items.length > 0 && Feeds.isNew(root.items[0], root.nowSec)
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
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.items

      delegate: Item {
        id: row
        required property var modelData
        width: ListView.view.width
        height: titleText.implicitHeight + sourceText.implicitHeight + Style.space(8)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(5)
          color: root.foreground
          opacity: rowMouse.containsMouse ? 0.07 : 0
        }

        Text {
          id: titleText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          y: Style.space(3)
          textFormat: Text.PlainText
          text: String(row.modelData.title || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          lineHeight: 1.05
        }

        Row {
          anchors.left: titleText.left
          anchors.top: titleText.bottom
          anchors.topMargin: Style.space(1)
          spacing: Style.space(5)

          Rectangle {
            visible: Feeds.isNew(row.modelData, root.nowSec)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(5)
            height: width
            radius: width / 2
            color: Color.accent
          }

          Text {
            id: sourceText
            textFormat: Text.PlainText
            text: Feeds.caption(row.modelData, root.nowSec)
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.modelData.link ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.open(row.modelData)
        }
      }
    }

    Text {
      visible: root.items.length === 0
      anchors.centerIn: list
      width: list.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: !root.sample ? "Loading…" : "Nothing to read. The gear picks feeds."
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
