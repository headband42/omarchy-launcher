import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

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

  property int selectedIndex: 0
  property var rows: []
  property bool catalogLoaded: false
  property bool catalogFailed: false

  readonly property string sectionId: String((root.settings && root.settings.sectionId) || "")
  readonly property bool busyOnly: !!(root.settings && root.settings.busyOnly)
  readonly property int contentWidth: Style.space(340)
  readonly property int currentIndex: {
    for (var i = 0; i < root.rows.length; i++) {
      if (String(root.rows[i].id) === root.sectionId) return i
    }
    return 0
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function commit(section, busy) {
    var next = { busyOnly: busy !== false }
    if (String(section)) next.sectionId = String(section)
    root.settings = next
    root.forceActiveFocus()
  }

  function choose(row) {
    if (!row) return
    root.commit(String(row.id), root.busyOnly)
  }

  function clearSection() {
    root.commit("", root.busyOnly)
  }

  function toggleBusy() {
    root.commit(root.sectionId, !root.busyOnly)
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.rows.length
    if (event.key === Qt.Key_Up && count > 0) {
      root.selectedIndex = (root.selectedIndex - 1 + count) % count
      return true
    }
    if (event.key === Qt.Key_Down && count > 0) {
      root.selectedIndex = (root.selectedIndex + 1) % count
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.choose(root.rows[root.selectedIndex])
      return true
    }
    if (event.key === Qt.Key_Delete) {
      root.clearSection()
      return true
    }
    if (event.key === Qt.Key_Space) {
      root.toggleBusy()
      return true
    }
    return false
  }

  Process {
    id: sectionProbe
    command: ["/usr/bin/python3", root.scriptPath("sample.py"), "--sections"]
    stdout: StdioCollector { id: sectionOut; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = null
      var ok = false
      try {
        parsed = JSON.parse(sectionOut.text || "")
        var rows = parsed && parsed.rows && parsed.rows.length ? parsed.rows : []
        if (rows.length) {
          root.rows = rows
          // Land the cursor on whatever is already saved, so opening the
          // panel and pressing Enter does not silently widen the section.
          root.selectedIndex = root.currentIndex
          ok = exitCode === 0
        }
      } catch (e) { ok = false }
      if (!ok) root.rows = []
      root.catalogLoaded = true
      root.catalogFailed = !ok
    }
  }

  implicitWidth: body.implicitWidth
  implicitHeight: body.implicitHeight

  Component.onCompleted: {
    sectionProbe.running = true
    root.forceActiveFocus()
  }

  Column {
    id: body
    width: root.contentWidth
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Herdr section"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.weight: Font.Medium
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Which part of the live session this tile watches: a whole workspace, one tab, or everything. Delete goes back to everything. The counts come from the session itself and include agents that are idle."
      color: root.foreground
      opacity: 0.58
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      height: Style.space(250)
      clip: true

      Text {
        anchors.fill: parent
        visible: root.catalogLoaded && root.rows.length < 1
        textFormat: Text.PlainText
        text: root.catalogFailed
          ? "Herdr is not answering, so there is nothing to pick"
          : "No sections in this session"
        color: root.foreground
        opacity: 0.58
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
      }

      ListView {
        id: sectionList
        anchors.fill: parent
        clip: true
        spacing: Style.space(3)
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        currentIndex: root.selectedIndex
        onCurrentIndexChanged: {
          if (currentIndex >= 0 && currentIndex < count) positionViewAtIndex(currentIndex, ListView.Contain)
        }

        delegate: BorderSurface {
          required property int index
          required property var modelData
          width: ListView.view.width
          height: Style.space(44)
          radius: root.cornerRadius
          color: index === root.selectedIndex ? root.hoverFill : "transparent"
          borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Rectangle {
              width: 6
              height: 6
              radius: 3
              anchors.verticalCenter: parent.verticalCenter
              visible: String(modelData.count) !== "0"
              color: root.foreground
              opacity: 0.5
            }

            Column {
              width: Math.max(0, parent.width - Style.space(64))
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.label || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: (index === root.selectedIndex
                              || String(modelData.id) === root.sectionId) ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.detail || "")
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Math.max(8, Style.font.caption - 2)
                elide: Text.ElideRight
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(modelData.count)
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = index
            onClicked: root.choose(modelData)
          }
        }
      }
    }

    BorderSurface {
      width: parent.width
      height: Style.space(48)
      radius: root.cornerRadius
      color: "transparent"
      borderSpec: Border.none()

      Row {
        id: busyRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(9)

        Column {
          width: busyRow.width - Style.space(64)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Only working or blocked"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Hides the idle and done ones"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        BorderSurface {
          width: Style.space(48)
          height: Style.space(26)
          anchors.verticalCenter: parent.verticalCenter
          radius: Style.space(13)
          color: root.busyOnly ? root.hoverFill : "transparent"
          borderSpec: root.busyOnly ? root.borderSpec : Border.none()

          Rectangle {
            id: knob
            width: 18
            height: 18
            radius: 9
            y: (parent.height - height) / 2
            x: root.busyOnly ? parent.width - width - y : y
            color: root.foreground
            opacity: root.busyOnly ? 0.9 : 0.35

            Behavior on x {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleBusy()
      }
    }
  }
}
