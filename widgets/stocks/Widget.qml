import QtQuick
import qs.Commons

Item {
  id: root
  property var tile: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  Text {
    textFormat: Text.PlainText
    text: "󰄨"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.32)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -Style.space(10)
  }

  Text {
    textFormat: Text.PlainText
    text: String((root.tile && root.tile.label) || "Stocks")
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.weight: Font.Medium
    elide: Text.ElideRight
    width: parent.width - Style.space(16)
    horizontalAlignment: Text.AlignHCenter
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(10)
  }
}
