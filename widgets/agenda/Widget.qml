import QtQuick
import qs.Commons
import "../_kit"
import "agenda.js" as Agenda

// The week and what is coming up, from the calendars the gear adds. The corner
// button flips to the month; a day there jumps the agenda to it. An event with
// a meeting link opens the meeting.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  property var sample: null
  property double nowMs: Date.now()
  property string view: "agenda"
  property int monthOffset: 0

  readonly property int weekStart: Qt.locale().firstDayOfWeek % 7
  readonly property bool h24: {
    var format = Qt.locale().timeFormat(Locale.ShortFormat)
    return format.indexOf("AP") < 0 && format.indexOf("ap") < 0 && format.indexOf("A") < 0 && format.indexOf("a") < 0
  }
  readonly property var events: root.sample && Array.isArray(root.sample.events) ? root.sample.events : []
  readonly property var counts: Agenda.countsByDay(root.events)
  readonly property var weekDays: Agenda.week(root.nowMs, root.weekStart, root.counts)
  readonly property var rows: Agenda.flatten(Agenda.agenda(root.events, root.nowMs, Agenda.AGENDA_DAYS, root.h24))
  readonly property var grid: Agenda.monthGrid(root.nowMs, root.monthOffset, root.weekStart, root.counts)
  readonly property bool hasCalendars: !!(root.sample && root.sample.calendars && root.sample.calendars.length > 0)
  readonly property int failing: {
    var n = 0
    var list = root.sample && root.sample.calendars ? root.sample.calendars : []
    for (var i = 0; i < list.length; i++) if (!list[i].ok) n++
    return n
  }

  readonly property var palette: [Color.accent, "#7aa2f7", "#9ece6a", "#e0af68", "#bb9af7", "#7dcfff", "#f7768e", "#73daca"]

  function calendarColor(index) {
    return root.palette[Math.abs(Number(index) || 0) % root.palette.length]
  }

  function showDay(key) {
    root.view = "agenda"
    var at = Agenda.indexOfDay(root.rows, key)
    if (at >= 0) Qt.callLater(function() { list.positionViewAtIndex(at, ListView.Beginning) })
  }

  Poller {
    script: Qt.resolvedUrl("agenda.py")
    interval: 300000
    active: root.visible
    onSampled: function(data) { if (data && data.ok === true) root.sample = data }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.visible
    onTriggered: root.nowMs = Date.now()
  }

  Item {
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      width: parent.width - controls.width - Style.space(4)
      title: root.view === "month" ? root.grid.title.toUpperCase() : Agenda.dateTitle(root.nowMs)
      trailing: root.view === "month" ? "" : (root.failing > 0 ? root.failing + " not loading" : Agenda.headerNote(root.events, root.nowMs))
      dotColor: root.failing > 0 ? Color.urgent : Color.accent
      dotOpacity: root.hasCalendars ? 1 : 0.35
      pulse: Agenda.headerNote(root.events, root.nowMs) === "now"
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Row {
      id: controls
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      spacing: 0

      IconButton {
        visible: root.view === "month"
        height: Style.space(20)
        glyph: "󰅁"
        glyphSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.monthOffset -= 1
      }

      IconButton {
        visible: root.view === "month"
        height: Style.space(20)
        glyph: "󰅂"
        glyphSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.monthOffset += 1
      }

      IconButton {
        height: Style.space(20)
        glyph: root.view === "month" ? "󰃮" : "󰸗"
        glyphSize: Style.font.caption
        tint: root.view === "month" ? Color.accent : root.foreground
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          root.monthOffset = 0
          root.view = root.view === "month" ? "agenda" : "month"
        }
      }
    }

    // —— Agenda: the week, then what is coming up ——

    Row {
      id: strip
      visible: root.view === "agenda"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      width: parent.width

      Repeater {
        model: root.weekDays

        Item {
          id: cell
          required property var modelData
          width: strip.width / 7
          height: Style.space(38)

          Text {
            id: letter
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: cell.modelData.name
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: letter.bottom
            anchors.topMargin: Style.space(1)
            width: Style.space(20)
            height: width
            radius: width / 2
            color: cell.modelData.today ? Color.accent : "transparent"

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(cell.modelData.day)
              color: cell.modelData.today ? Color.menu.background : root.foreground
              opacity: cell.modelData.past && !cell.modelData.today ? 0.45 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: cell.modelData.today ? Font.DemiBold : Font.Normal
            }
          }

          Rectangle {
            visible: cell.modelData.count > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: Style.space(4)
            height: width
            radius: width / 2
            color: root.foreground
            opacity: cell.modelData.past ? 0.25 : 0.6
          }
        }
      }
    }

    ListView {
      id: list
      visible: root.view === "agenda"
      anchors.top: strip.bottom
      anchors.topMargin: Style.space(4)
      anchors.bottom: parent.bottom
      width: parent.width
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.rows

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool isDay: modelData.kind === "day"
        readonly property var event: modelData.event || ({})
        width: ListView.view.width
        height: isDay ? Style.space(index === 0 ? 16 : 22) : Style.space(21)

        Text {
          visible: row.isDay
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(2)
          textFormat: Text.PlainText
          text: row.isDay ? row.modelData.label.toUpperCase() : ""
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 0.5
        }

        Rectangle {
          visible: !row.isDay
          anchors.fill: parent
          radius: Style.space(4)
          color: root.foreground
          opacity: eventMouse.containsMouse && row.event.link ? 0.07 : 0
        }

        Rectangle {
          id: bar
          visible: !row.isDay
          x: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(3)
          height: parent.height - Style.space(6)
          radius: width / 2
          color: root.calendarColor(row.event.calendar)
        }

        Text {
          id: when
          visible: !row.isDay
          anchors.left: bar.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(root.h24 ? 38 : 50)
          textFormat: Text.PlainText
          text: String(row.event.time || "")
          color: row.event.now ? Color.accent : root.foreground
          opacity: row.event.now ? 1 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
          elide: Text.ElideRight
        }

        Text {
          visible: !row.isDay
          anchors.left: when.right
          anchors.leftMargin: Style.space(4)
          anchors.right: linkGlyph.visible ? linkGlyph.left : parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(row.event.title || "")
          color: row.event.now ? Color.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.weight: row.event.now ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
        }

        Text {
          id: linkGlyph
          visible: !row.isDay && !!row.event.link
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰍫"
          color: row.event.now ? Color.accent : root.foreground
          opacity: eventMouse.containsMouse ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: eventMouse
          visible: !row.isDay && !!row.event.link
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.host && root.host.openLink) root.host.openLink(String(row.event.link))
        }
      }
    }

    Text {
      visible: root.view === "agenda" && root.rows.length === 0
      anchors.top: strip.bottom
      anchors.topMargin: Style.space(16)
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: !root.sample ? "Loading…"
        : (root.hasCalendars ? "Nothing in the next two weeks" : "Add a calendar with the gear: paste its iCal address")
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // —— Month ——

    Column {
      visible: root.view === "month"
      anchors.top: header.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: parent.bottom
      width: parent.width

      Row {
        width: parent.width

        Repeater {
          model: Agenda.weekdayLetters(root.weekStart)

          Text {
            required property var modelData
            width: parent.width / 7
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: modelData
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Grid {
        id: monthCells
        width: parent.width
        columns: 7

        Repeater {
          model: root.grid.cells

          Item {
            id: day
            required property var modelData
            width: monthCells.width / 7
            height: Math.floor((monthCells.parent.height - Style.font.caption - Style.space(4)) / 6)

            Rectangle {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(2)
              width: Math.min(parent.width, parent.height) - Style.space(4)
              height: width
              radius: width / 2
              color: day.modelData.today ? Color.accent : root.foreground
              opacity: day.modelData.today ? 1 : (dayMouse.containsMouse ? 0.1 : 0)
            }

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(2)
              textFormat: Text.PlainText
              text: String(day.modelData.day)
              color: day.modelData.today ? Color.menu.background : root.foreground
              opacity: day.modelData.inMonth ? 1 : 0.3
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: day.modelData.today ? Font.DemiBold : Font.Normal
            }

            Rectangle {
              visible: day.modelData.count > 0
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(1)
              width: Style.space(3)
              height: width
              radius: width / 2
              color: root.foreground
              opacity: day.modelData.inMonth ? 0.6 : 0.25
            }

            MouseArea {
              id: dayMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showDay(day.modelData.key)
            }
          }
        }
      }
    }
  }
}
