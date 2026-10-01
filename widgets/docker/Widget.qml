import QtQuick
import Quickshell.Io
import qs.Commons
import "../_kit"
import "../_kit/kit.js" as Kit
import "docker.js" as Docker

// Containers at a glance: how many run, which need attention, and the
// loudest few with their image and load. Hovering a row offers start, stop,
// or restart. A click anywhere else launches Opens (lazydocker by default).
// Without access to the socket it says why, and what the daemon is doing.
Item {
  id: root
  clip: true
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ ok: false, mode: "", rows: [] })
  property bool loaded: false
  // The container an action is running against, and how the last one went.
  property string busyId: ""
  property string busyAction: ""
  property string errorId: ""
  property string errorText: ""

  readonly property var rows: Docker.toList(root.sample && root.sample.rows)
  readonly property bool listing: root.loaded && !!root.sample.ok && root.sample.mode === "rows"
  readonly property var statList: Docker.stats(root.sample)
  readonly property int total: root.listing
    ? (Number(root.sample.running) || 0) + (Number(root.sample.paused) || 0) + (Number(root.sample.stopped) || 0)
    : 0

  readonly property color warnTone: Qt.rgba(0.86, 0.68, 0.30, 1)

  function toneColor(tone) {
    if (tone === "bad") return Color.urgent
    if (tone === "warn") return root.warnTone
    if (tone === "ok") return Color.accent
    return root.foreground
  }

  function openTui() {
    // Launch before the launcher closes. lazydocker needs a terminal.
    Util.execArgv(["omarchy-launch-tui", "omarchy-launch-docker-tui"])
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  function act(row, action) {
    if (actor.running || !row || !row.id) return
    root.busyId = String(row.id)
    root.busyAction = action
    root.errorId = ""
    root.errorText = ""
    actor.command = ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("docker.py")),
      "--action", action, "--id", String(row.id)]
    actor.running = true
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("docker.py")
    interval: 10000
    active: root.visible && !actor.running
    onSampled: function(data) {
      if (!data) return
      root.sample = data
      root.loaded = true
    }
  }

  Process {
    id: actor
    stdout: StdioCollector { id: actOut; waitForEnd: true }
    onExited: {
      var data = null
      try { data = JSON.parse(actOut.text || "") } catch (e) { data = null }
      if (data) {
        root.sample = data
        root.loaded = true
      }
      var result = data && data.action
      if (!result || !result.ok) {
        root.errorId = root.busyId
        root.errorText = result && result.error ? String(result.error) : (root.busyAction + " failed")
        clearError.restart()
      }
      root.busyId = ""
      root.busyAction = ""
    }
  }

  Timer {
    id: clearError
    interval: 8000
    onTriggered: {
      root.errorId = ""
      root.errorText = ""
    }
  }

  TextMetrics {
    id: rowMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: "Ag"
  }

  TextMetrics {
    id: detailMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Ag"
  }

  Item {
    id: content
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "DOCKER"
      trailing: root.listing ? Docker.usageLine(root.sample) : ""
      dotColor: !root.listing ? root.foreground
        : (Number(root.sample.unhealthy) > 0 ? Color.urgent : (Number(root.sample.running) > 0 ? Color.accent : root.foreground))
      dotOpacity: root.listing && Number(root.sample.running) > 0 ? 1 : 0.35
      pulse: actor.running
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // No socket, no daemon, or no Docker: say which, and what still works.
    Column {
      visible: root.loaded && !root.listing
      anchors.centerIn: parent
      width: parent.width
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: ""
        color: root.foreground
        opacity: 0.25
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge * 2
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Docker.statusLabel(root.sample)
        color: root.foreground
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      Text {
        visible: text.length > 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Docker.statusDetail(root.sample)
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item { width: 1; height: Style.space(6) }

      IconButton {
        visible: Docker.canOpen(root.sample)
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(28)
        glyph: ""
        label: "Open lazydocker"
        filled: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openTui()
      }

      Item { width: 1; height: Style.space(4) }

      Text {
        visible: text.length > 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Docker.statusHint(root.sample)
        color: root.foreground
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    // Running, unhealthy, paused, stopped: the numbers first.
    Row {
      id: statRow
      visible: root.listing
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right

      Repeater {
        model: root.statList

        Column {
          required property var modelData
          width: statRow.width / Math.max(1, root.statList.length)
          spacing: 0

          Text {
            textFormat: Text.PlainText
            text: String(modelData.count)
            color: modelData.count > 0 && modelData.tone !== "off" ? root.toneColor(modelData.tone) : root.foreground
            opacity: modelData.count > 0 ? 1 : 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge + Style.space(4)
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
          }

          Text {
            textFormat: Text.PlainText
            text: modelData.label
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Item {
      id: list
      visible: root.listing
      anchors.top: statRow.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      readonly property int rowHeight: Math.ceil(rowMetric.height + detailMetric.height) + Style.space(9)
      readonly property int moreHeight: Math.ceil(detailMetric.height) + Style.space(6)
      readonly property var plan: Docker.rowPlan(root.total, list.height - Style.space(5), list.rowHeight, list.moreHeight)
      readonly property int shown: Math.min(list.plan.rows, root.rows.length)

      Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: root.foreground
        opacity: 0.08
      }

      Text {
        visible: root.rows.length === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "No containers"
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Column {
        y: Style.space(5)
        width: parent.width

        Repeater {
          model: list.shown

          Item {
            id: row
            required property int index
            readonly property var box: root.rows[index] || ({})
            readonly property bool busy: root.busyId !== "" && root.busyId === String(row.box.id || "")
            readonly property bool failed: root.errorId !== "" && root.errorId === String(row.box.id || "")
            readonly property var actions: Docker.actionsFor(row.box)
            readonly property bool showActions: (hover.containsMouse || row.busy) && row.actions.length > 0
            width: list.width
            height: list.rowHeight

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -Style.space(4)
              anchors.rightMargin: -Style.space(4)
              radius: Style.space(6)
              color: root.foreground
              opacity: hover.containsMouse ? 0.06 : 0
            }

            // Hover only: a click still falls through to the tile's Opens.
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
            }

            Rectangle {
              id: dot
              anchors.left: parent.left
              y: Math.round(nameText.y + (nameText.height - height) / 2)
              width: Style.space(7)
              height: width
              radius: width / 2
              color: row.box.tone === "off" ? "transparent" : root.toneColor(row.box.tone)
              border.width: row.box.tone === "off" ? 1 : 0
              border.color: root.foreground
              opacity: row.box.tone === "off" ? 0.45 : 1
            }

            Text {
              id: nameText
              anchors.left: dot.right
              anchors.leftMargin: Style.space(8)
              anchors.right: rightTop.left
              anchors.rightMargin: Style.space(6)
              y: Style.space(4)
              textFormat: Text.PlainText
              text: String(row.box.name || "")
              color: root.foreground
              opacity: row.box.running || row.box.state === "paused" ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              anchors.left: nameText.left
              anchors.right: rightBottom.left
              anchors.rightMargin: Style.space(6)
              anchors.top: nameText.bottom
              textFormat: Text.PlainText
              text: row.failed ? root.errorText : Docker.rowDetail(row.box)
              color: row.failed ? Color.urgent : root.foreground
              opacity: row.failed ? 0.9 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Item {
              id: rightTop
              anchors.right: parent.right
              anchors.verticalCenter: nameText.verticalCenter
              width: row.showActions ? actionRow.width : statusText.implicitWidth
              height: nameText.height

              Text {
                id: statusText
                visible: !row.showActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(row.box.short || "")
                color: row.box.tone === "bad" || row.box.tone === "warn" ? root.toneColor(row.box.tone) : root.foreground
                opacity: row.box.tone === "bad" || row.box.tone === "warn" ? 0.95 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                id: actionRow
                visible: row.showActions
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Repeater {
                  model: row.actions

                  IconButton {
                    required property string modelData
                    height: Style.space(22)
                    glyph: modelData === "start" ? "" : (modelData === "stop" ? "" : "")
                    glyphSize: Style.font.bodySmall
                    tint: modelData === "stop" ? Color.urgent : root.foreground
                    busy: row.busy && root.busyAction === modelData
                    available: !actor.running || row.busy
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.act(row.box, modelData)
                  }
                }
              }
            }

            Text {
              id: rightBottom
              anchors.right: parent.right
              anchors.top: nameText.bottom
              textFormat: Text.PlainText
              text: Docker.rowUsage(row.box)
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.features: ({ "tnum": 1 })
            }
          }
        }

        Text {
          visible: root.total - list.shown > 0
          width: list.width
          height: list.moreHeight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: "+" + (root.total - list.shown) + " more in lazydocker"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
