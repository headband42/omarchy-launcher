import QtQuick
import qs.Commons
import qs.Ui
import "timer.js" as Countdown

// The lengths on the tile's buttons: up to four, at least one.
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

  readonly property var choices: Countdown.CHOICES
  readonly property var picked: Countdown.presets(root.settings)
  readonly property bool full: root.picked.length >= Countdown.MAX_PRESETS

  implicitWidth: Style.space(320)
  implicitHeight: column.implicitHeight + Style.space(24)

  function toggle(minutes) {
    root.settings = Countdown.togglePreset(root.settings, minutes)
    root.forceActiveFocus()
  }

  function handleEscape() {
    return false
  }

  function handleKey(event) {
    if (!event) return false
    var count = root.choices.length
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
      root.selectedIndex = (root.selectedIndex - 1 + count) % count
      return true
    }
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
      root.selectedIndex = (root.selectedIndex + 1) % count
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.toggle(root.choices[root.selectedIndex])
      return true
    }
    return false
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(12)
    spacing: Style.space(10)

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "The buttons on the tile, up to four. Each starts an Omarchy reminder that notifies you when it ends."
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.choices

        BorderSurface {
          id: pill
          required property var modelData
          required property int index
          readonly property bool on: root.picked.indexOf(modelData) >= 0
          readonly property bool blocked: !pill.on && root.full
          width: Style.space(64)
          height: Style.space(32)
          radius: height / 2
          color: pill.on ? Util.alpha(Color.accent, 0.28)
            : (index === root.selectedIndex ? root.hoverFill : Util.alpha(root.foreground, 0.06))
          borderSpec: index === root.selectedIndex ? root.borderSpec : Border.none()

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: Countdown.fmtPreset(pill.modelData)
            color: root.foreground
            opacity: pill.blocked ? 0.35 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: pill.on ? Font.DemiBold : Font.Normal
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pill.blocked ? Qt.ArrowCursor : Qt.PointingHandCursor
            onEntered: root.selectedIndex = pill.index
            onClicked: {
              root.selectedIndex = pill.index
              root.toggle(pill.modelData)
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.picked.length + " of " + Countdown.MAX_PRESETS + (root.full ? " · turn one off to pick another" : "")
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
