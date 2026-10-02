import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../_kit"
import "media.js" as Media

// Whatever is playing over MPRIS: a browser tab, mpv, VLC, Spotify, a podcast
// app. Playing beats paused; the corner button switches when several players
// have something loaded. Nothing is polled.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  // Which player the user switched to. Lives as long as the launcher is open.
  property string pinnedKey: ""

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: Media.pickPlayer(root.players, root.pinnedKey)

  // What the tile draws, read off the player.
  property bool hasTrack: Media.hasTrack(root.player)
  property bool playing: !!root.player && root.player.isPlaying
  property string title: root.player ? String(root.player.trackTitle || "") : ""
  property string subtitle: root.player ? Media.artistLine(root.player.trackArtist, root.player.trackAlbum) : ""
  property string artUrl: root.player ? String(root.player.trackArtUrl || "") : ""
  property string playerLabel: Media.playerName(root.player)
  property int playerCount: Media.switchable(root.players).length
  property real length: root.player && root.player.lengthSupported ? Math.max(0, Number(root.player.length) || 0) : 0
  property real position: root.player && root.player.positionSupported ? Math.max(0, Number(root.player.position) || 0) : 0
  property bool canPrevious: !!root.player && root.player.canControl && root.player.canGoPrevious
  property bool canNext: !!root.player && root.player.canControl && root.player.canGoNext
  property bool canToggle: !!root.player && root.player.canControl && root.player.canTogglePlaying

  readonly property bool seekable: root.length > 0 && !!root.player && root.player.canControl
    && root.player.canSeek && root.player.positionSupported

  // MprisPlayer.position only notifies on a jump. Ask for it while the tile shows.
  function refreshPosition() {
    if (root.player) root.player.positionChanged()
  }

  function seekTo(seconds) {
    if (!root.seekable) return
    root.player.position = seconds
    root.refreshPosition()
  }

  function raisePlayer() {
    if (!root.player || !root.player.canRaise) return
    root.player.raise()
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  function nudgeVolume(angle) {
    if (!root.player || !root.player.canControl || !root.player.volumeSupported) return
    root.player.volume = Media.stepVolume(root.player.volume, angle)
  }

  onVisibleChanged: if (visible) root.refreshPosition()
  onPlayerChanged: root.refreshPosition()

  Timer {
    interval: 1000
    repeat: true
    running: root.visible && root.playing && root.length > 0
    onTriggered: root.refreshPosition()
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onPostTrackChanged() { root.refreshPosition() }
  }

  component TransportControl: Item {
    id: control
    property string glyph: ""
    property real glyphSize: Style.font.icon
    property bool available: true
    property bool filled: false
    property color foreground: Color.menu.text
    property string fontFamily: Style.font.menuFamily
    signal clicked()

    width: height
    height: Style.space(28)

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: control.foreground
      opacity: !control.available ? 0 : (controlMouse.containsMouse ? 0.22 : (control.filled ? 0.14 : 0))
    }

    OpticalGlyph {
      anchors.fill: parent
      text: control.glyph
      fontFamily: control.fontFamily
      fontSize: control.glyphSize
      color: control.foreground
      opacity: !control.available ? 0.25 : (control.filled ? 1 : 0.75)
    }

    MouseArea {
      id: controlMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: control.available ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (control.available) control.clicked()
    }
  }

  // The artwork, blurred, behind everything. Inset a pixel so the tile's
  // border still shows.
  Item {
    id: backdrop
    z: 1
    anchors.fill: parent
    anchors.margins: 1
    visible: root.hasTrack && backArt.status === Image.Ready

    // Omarchy's Background.qml masks the same way. Where shader effects
    // cannot run, the layer draws nothing and the tile keeps its plain fill.
    Image {
      id: backArt
      anchors.fill: parent
      source: root.hasTrack ? root.artUrl : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 128
      sourceSize.height: 128
      opacity: 0.55
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1
        blurMax: 40
        saturation: 0.2
        maskEnabled: true
        maskSource: backMask
      }
    }

    Rectangle {
      id: backMask
      anchors.fill: parent
      radius: Math.max(0, Style.cornerRadius - 1)
      visible: false
      layer.enabled: true
    }

    Rectangle {
      anchors.fill: parent
      radius: backMask.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.45) }
        GradientStop { position: 0.55; color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.55) }
        GradientStop { position: 1.0; color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.9) }
      }
    }
  }

  // The wheel changes the player's own volume. No buttons: a click still
  // reaches the grid or a control.
  MouseArea {
    z: 1
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      root.nudgeVolume(wheel.angleDelta.y)
      wheel.accepted = true
    }
  }

  Item {
    id: content
    z: 2
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      width: parent.width - (switcher.visible ? switcher.width + Style.space(4) : 0)
      title: "MEDIA"
      trailing: root.hasTrack ? root.playerLabel : ""
      dotColor: root.playing ? Color.accent : root.foreground
      dotOpacity: root.playing ? 1 : 0.35
      pulse: root.playing
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    IconButton {
      id: switcher
      visible: root.playerCount > 1
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      height: Style.space(20)
      glyph: "󰓡"
      glyphSize: Style.font.caption
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.pinnedKey = Media.nextKey(root.players, Media.playerKey(root.player))
    }

    Column {
      visible: !root.hasTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: header.height / 2
      spacing: Style.space(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "󰝚"
        color: root.foreground
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2.2)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Nothing playing"
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Play something in any app"
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }

    Row {
      id: controls
      visible: root.hasTrack
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰒮"
        available: root.canPrevious
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.player.previous()
      }

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(34)
        glyph: root.playing ? "󰏤" : "󰐊"
        glyphSize: Style.font.iconLarge
        filled: true
        available: root.canToggle
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.player.togglePlaying()
      }

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰒭"
        available: root.canNext
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.player.next()
      }
    }

    Item {
      id: times
      visible: root.hasTrack && root.length > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: controls.top
      anchors.bottomMargin: Style.space(4)
      height: visible ? Style.font.caption + 2 : 0

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Media.fmtTime(root.position)
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "-" + Media.fmtTime(Math.max(0, root.length - root.position))
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: bar
      visible: times.visible
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: times.top
      height: visible ? Style.space(10) : 0

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: barMouse.containsMouse && root.seekable ? Style.space(6) : Style.space(4)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

        Rectangle {
          width: parent.width * Media.progress(root.position, root.length)
          height: parent.height
          radius: parent.radius
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.Linear } }
        }
      }

      MouseArea {
        id: barMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) { root.seekTo(Media.seekTarget(mouse.x, width, root.length)) }
      }
    }

    // Artwork and title. A click brings the player's window forward.
    Item {
      id: info
      visible: root.hasTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.bottom: bar.visible ? bar.top : controls.top
      anchors.bottomMargin: Style.space(6)

      MouseArea {
        anchors.fill: parent
        enabled: !!root.player && root.player.canRaise
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.raisePlayer()
      }

      Item {
        id: art
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.round(Math.min(info.height, info.width * 0.4)))
        height: width

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          visible: cover.status !== Image.Ready
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

          OpticalGlyph {
            anchors.fill: parent
            text: "󰝚"
            fontFamily: root.fontFamily
            fontSize: Math.max(Style.font.icon, Math.round(parent.height * 0.38))
            color: root.foreground
            opacity: 0.45
          }
        }

        Image {
          id: cover
          anchors.fill: parent
          source: root.hasTrack ? root.artUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: width * 2
          sourceSize.height: height * 2
        }
      }

      Column {
        anchors.left: art.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text.length > 0
          textFormat: Text.PlainText
          text: root.subtitle
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }
    }
  }
}
