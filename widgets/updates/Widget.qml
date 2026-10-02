import QtQuick
import qs.Commons
import "../_kit"
import "updates.js" as Updates

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ ok: true, count: 0, names: [], omarchy: [], channel: "", version: "", lastUpgradeAt: 0 })
  property double nowMs: Date.now()

  readonly property int count: Math.max(0, Number(sample.count) || 0)
  readonly property bool busy: poller.running && !sample.count && !sample.names
  readonly property string ago: Updates.fmtAgo(root.nowMs, sample.lastUpgradeAt)
  readonly property string versionLine: {
    var parts = []
    if (root.ago) parts.push("updated " + root.ago)
    else parts.push("never updated")
    if (root.sample.version) parts.push(String(root.sample.version))
    return parts.join(" · ")
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("updates.py")
    interval: 1800000
    active: root.visible
    onSampled: function(data) { if (data) root.sample = data }
  }

  Timer {
    interval: 60000
    running: root.visible
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Column {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

    WidgetHeader {
      title: "UPDATES"
      trailing: String(root.sample.channel || "")
      dotColor: root.count > 0 ? Color.accent : root.foreground
      dotOpacity: root.count > 0 ? 1 : 0.35
      pulse: root.count > 0
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Item {
      width: parent.width
      height: Style.font.title + 6

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.busy ? "…" : (root.count > 0 ? String(root.count) : "✓")
        color: root.count > 0 ? Color.accent : root.foreground
        opacity: root.count > 0 ? 1 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(root.count > 0 && root.count < 10 ? 16 : 24)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.busy ? "checking" : (root.count > 0 ? (root.count === 1 ? "package" : "packages") : (root.sample.ok ? "up to date" : "couldn't check"))
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.versionLine
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: (root.sample.omarchy || []).length > 0
      textFormat: Text.PlainText
      text: (root.sample.omarchy || []).length > 0 ? String(root.sample.omarchy[0]) : ""
      color: Color.accent
      opacity: 0.85
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
