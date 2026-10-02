import QtQuick
import qs.Commons
import "../_kit"
import "status.js" as Status

// Status pages for the services the user depends on, problems first. A row
// opens that service's page, or the incident when there is one.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowSec: Date.now() / 1000

  readonly property var picked: Status.services(root.tile && root.tile.settings)
  readonly property var rows: Status.sortRows(root.sample ? root.sample.services : [])
  readonly property bool anyProblem: root.rows.length > 0 && Status.isProblem(root.rows[0].state)

  // Healthy is quiet: a dim dot in the text color. Only trouble takes a color,
  // since a theme's accent can be orange or red and would read as a warning.
  function stateColor(state) {
    var s = String(state || "")
    if (s === "maintenance") return Color.muted
    if (Status.isProblem(s)) return Color.urgent
    return root.foreground
  }

  function stateOpacity(state) {
    var s = String(state || "")
    if (s === "none") return 0.35
    if (s === "unknown") return 0.2
    if (s === "minor") return 0.75
    return 1
  }

  function open(row) {
    var link = String(row && (row.link || row.page) || "")
    if (link && root.host && root.host.openLink) root.host.openLink(link)
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("status.py")
    args: ["--services", JSON.stringify(root.picked)]
    interval: 120000
    active: root.visible
    onSampled: function(data) { if (data && data.ok === true) root.sample = data }
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
      title: "STATUS"
      trailing: root.sample ? Status.headerNote(root.rows) : ""
      dotColor: root.anyProblem ? Color.urgent : Color.accent
      dotOpacity: root.sample ? 1 : 0.35
      pulse: root.anyProblem || poller.running && !root.sample
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
        readonly property bool problem: modelData.state !== "none"
        width: ListView.view.width
        height: problem ? Style.space(38) : Style.space(24)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(5)
          color: root.foreground
          opacity: rowMouse.containsMouse ? 0.07 : 0
        }

        Text {
          id: name
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.right: badge.left
          anchors.rightMargin: Style.space(6)
          y: row.problem ? Style.space(3) : Math.round((parent.height - height) / 2)
          textFormat: Text.PlainText
          text: String(row.modelData.name || "")
          color: root.foreground
          opacity: row.problem ? 1 : 0.85
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: row.problem ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
        }

        Text {
          visible: row.problem
          anchors.left: name.left
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.top: name.bottom
          textFormat: Text.PlainText
          text: String(row.modelData.summary || "")
          color: root.stateColor(row.modelData.state)
          opacity: row.modelData.state === "unknown" ? 0.5 : Math.max(0.6, root.stateOpacity(row.modelData.state))
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Row {
          id: badge
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: name.verticalCenter
          spacing: Style.space(6)

          Text {
            visible: text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: row.modelData.latency !== null && row.modelData.latency !== undefined && row.modelData.state === "none"
              ? row.modelData.latency + " ms" : (row.problem ? Status.stateLabel(row.modelData.state) : "")
            color: row.problem ? root.stateColor(row.modelData.state) : root.foreground
            opacity: row.problem ? Math.max(0.6, root.stateOpacity(row.modelData.state)) : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: root.stateColor(row.modelData.state)
            opacity: root.stateOpacity(row.modelData.state)
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.open(row.modelData)
        }
      }
    }

    Text {
      visible: !root.sample
      anchors.centerIn: list
      textFormat: Text.PlainText
      text: "Checking…"
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
