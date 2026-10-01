import QtQuick
import qs.Commons
import "../_kit"
import "timezones.js" as Zones

Item {
  id: root
  clip: true
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  property int tick: 0

  readonly property var zoneEntries: Zones.normalizeZones(root.tile && root.tile.settings)
  readonly property var zoneIds: {
    var entries = root.zoneEntries
    var ids = []
    for (var i = 0; i < entries.length; i++) ids.push(String(entries[i].id || ""))
    return ids
  }
  readonly property bool hour12: {
    var fmt = ""
    try { fmt = String(Qt.locale().timeFormat(Locale.ShortFormat) || "") } catch (e) { fmt = "" }
    return fmt.indexOf("AP") >= 0 || fmt.indexOf("ap") >= 0
  }
  readonly property int localOffset: {
    var local = root.sample && root.sample.local
    if (local && local.offsetMinutes !== undefined && local.offsetMinutes !== null)
      return Number(local.offsetMinutes)
    return -new Date().getTimezoneOffset()
  }
  readonly property string localLabel: {
    var local = root.sample && root.sample.local
    if (local && local.label) return String(local.label)
    return "Local"
  }
  readonly property string localAbbr: {
    var local = root.sample && root.sample.local
    return local && local.abbr ? String(local.abbr) : ""
  }
  readonly property string localTime: {
    var _tick = root.tick
    return Zones.formatTime(Date.now(), root.localOffset, root.hour12)
  }
  readonly property string localDate: {
    var _tick = root.tick
    return Zones.formatDate(Date.now(), root.localOffset)
  }
  readonly property int heroPx: {
    var rows = root.zoneRows.length
    var ratio = rows === 0 ? 0.26 : (rows >= 3 ? 0.16 : 0.2)
    var px = Math.round(Math.min(root.width * 0.86, root.height * ratio))
    return Math.max(Style.font.heading, px)
  }
  readonly property bool showDate: root.zoneRows.length === 0 || root.height >= Style.space(168)

  readonly property var zoneRows: {
    var _tick = root.tick
    var entries = root.zoneEntries
    var byId = {}
    var listed = (root.sample && root.sample.zones) || []
    for (var i = 0; i < listed.length; i++) {
      if (listed[i] && listed[i].id) byId[String(listed[i].id)] = listed[i]
    }
    var out = []
    var now = Date.now()
    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j]
      var info = byId[entry.id] || null
      var known = info && info.offsetMinutes !== undefined && info.offsetMinutes !== null
      var delta = known ? Zones.dayDelta(now, root.localOffset, info.offsetMinutes) : 0
      out.push({
        id: entry.id,
        label: entry.label || (info && info.label) || Zones.cityOf(entry.id),
        time: known ? Zones.formatTime(now, info.offsetMinutes, root.hour12) : "—",
        delta: known ? Zones.formatDayDelta(delta) : ""
      })
    }
    return out
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("timezones.py")
    args: ["--clocks"].concat(root.zoneIds)
    interval: 60000
    active: root.visible
    onSampled: function(data) { if (data && typeof data === "object") root.sample = data }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    onTriggered: root.tick++
  }

  onVisibleChanged: if (visible) root.tick++

  Item {
    anchors.fill: parent
    anchors.margins: Style.space(10)

    Column {
      id: stack
      width: parent.width
      spacing: Style.space(4)
      y: Math.max(0, Math.round((parent.height - height) / 2))

      Item {
        width: parent.width
        height: kicker.implicitHeight

        Text {
          id: kicker
          anchors.left: parent.left
          anchors.right: abbrText.left
          anchors.rightMargin: Style.space(6)
          textFormat: Text.PlainText
          text: root.localLabel.toUpperCase()
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          font.letterSpacing: 1
          elide: Text.ElideRight
        }

        Text {
          id: abbrText
          anchors.right: parent.right
          anchors.verticalCenter: kicker.verticalCenter
          textFormat: Text.PlainText
          text: root.localAbbr
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.localTime
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.heroPx
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
        elide: Text.ElideRight
      }

      Text {
        visible: root.showDate
        width: parent.width
        textFormat: Text.PlainText
        text: root.localDate
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Rectangle {
        visible: root.zoneRows.length > 0
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }

      Column {
        visible: root.zoneRows.length > 0
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.zoneRows

          Item {
            required property var modelData
            width: parent.width
            height: zoneTime.implicitHeight

            Text {
              id: zoneTime
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.time
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }

            Text {
              id: zoneDelta
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: String(modelData.delta || "").length > 0
              textFormat: Text.PlainText
              text: modelData.delta
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.left: zoneTime.right
              anchors.leftMargin: Style.space(8)
              anchors.right: zoneDelta.visible ? zoneDelta.left : parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.label
              color: root.foreground
              opacity: 0.72
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
