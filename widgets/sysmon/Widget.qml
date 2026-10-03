import QtQuick
import qs.Commons
import "../_kit"
import "../_kit/system.js" as Sys

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  // The latest usage sample, the hardware specs read once per open, and the
  // CPU % worked out between samples.
  property var sample: ({})
  property var specs: ({})
  property var cpuState: ({ ticks: null, at: 0, cpu: null })
  property var peaks: ({})

  readonly property var meters: Sys.meters(root.sample, root.cpuState.cpu)
  readonly property real hot: Sys.hottest(root.meters)
  readonly property var specLines: Sys.specLines(root.specs)

  function take(data) {
    if (!data) return
    root.cpuState = Sys.cpuStep(root.cpuState, data, Date.now())
    root.sample = data
    root.peaks = Sys.peaksStep(root.peaks, root.meters)
  }

  Poller {
    script: Qt.resolvedUrl("../_kit/system.py")
    interval: 1200
    active: root.visible
    onSampled: function(data) { root.take(data) }
  }

  // Once per open: the specs, and a CPU reading over a short window so the
  // bar has a figure before there are two samples to compare.
  Poller {
    script: Qt.resolvedUrl("../_kit/system.py")
    args: ["--warm", "--specs"]
    interval: 0
    active: root.visible
    onSampled: function(data) {
      if (!data) return
      root.specs = data
      root.take(data)
    }
  }

  Text { id: pctGauge; visible: false; text: "100%"; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.weight: Font.DemiBold }
  Text { id: labelGauge; visible: false; text: "VRAM"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.weight: Font.Medium }
  Text { id: subGauge; visible: false; text: "0"; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    WidgetHeader {
      id: header
      title: "SYSTEM"
      dotColor: Sys.fill(root.hot, root.foreground, Color.urgent)
      dotOpacity: Sys.isHot(root.hot) ? 1 : 0.45
      pulse: Sys.isHot(root.hot)
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    Item {
      id: barsWrap
      width: parent.width
      height: parent.height - header.height - (specWrap.visible ? specWrap.height + parent.spacing : 0) - parent.spacing

      // Each meter gets an even share of the height. The bars thicken and the
      // gaps open as the tile grows, rather than a small stack floating in
      // the middle of it.
      readonly property int count: Math.max(1, root.meters.length)
      readonly property int labelW: labelGauge.implicitWidth + Style.space(8)
      readonly property int pctW: pctGauge.implicitWidth
      readonly property int barH: Math.max(Style.space(6), Math.min(Style.space(10), Math.round(height / count * 0.17)))
      readonly property int rowH: pctGauge.implicitHeight + Style.space(2) + subGauge.implicitHeight
      readonly property int gap: Math.max(Style.space(3), Math.min(Style.space(28), Math.floor((height - count * rowH) / count)))

      Column {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: barsWrap.gap

        // A row count, not the rows themselves: a new array each sample would
        // rebuild every row, and the bars would jump instead of sliding.
        Repeater {
          model: root.meters.length

          Column {
            id: meter
            required property int index
            readonly property var row: root.meters[meter.index] || ({})
            readonly property real peak: Number(root.peaks[meter.row.key]) || 0
            width: stack.width
            spacing: Style.space(2)

            Item {
              width: parent.width
              height: pctGauge.implicitHeight

              Text {
                width: barsWrap.labelW
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: String(meter.row.label || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Rectangle {
                id: track
                x: barsWrap.labelW
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - barsWrap.labelW - barsWrap.pctW - Style.space(8)
                height: barsWrap.barH
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                Rectangle {
                  width: Math.max(height, (Number(meter.row.value) || 0) * parent.width)
                  height: parent.height
                  radius: parent.radius
                  visible: (Number(meter.row.value) || 0) > 0
                  color: Sys.fill(meter.row.value, root.foreground, Color.urgent)
                  Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                  visible: meter.peak > 0.02 && meter.peak > (Number(meter.row.value) || 0) + 0.01
                  width: Math.max(2, Style.space(2))
                  height: parent.height + Style.space(2)
                  radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.min(parent.width - width, Math.max(0, meter.peak * parent.width - width / 2))
                  color: root.foreground
                  opacity: 0.45
                  Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
              }

              Text {
                anchors.right: parent.right
                width: barsWrap.pctW
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: String(meter.row.pct || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
            }

            Text {
              x: barsWrap.labelW
              width: parent.width - x
              textFormat: Text.PlainText
              text: String(meter.row.sub || "")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    Column {
      id: specWrap
      visible: root.specLines.length > 0
      width: parent.width
      spacing: Style.space(4)

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }

      Column {
        width: parent.width
        spacing: 1

        Repeater {
          model: root.specLines

          Text {
            required property var modelData
            width: parent.width
            textFormat: Text.PlainText
            text: String(modelData)
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
