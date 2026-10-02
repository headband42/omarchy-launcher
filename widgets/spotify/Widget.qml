import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../_kit"
import "spotify.js" as Spotify

// Reads OmaSpotify's local player over MPRIS, in-process. Nothing is polled.
// Playback on another Connect device (a phone, a speaker) has no MPRIS player
// here, so the tile shows idle until this computer plays again.
Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text

  readonly property var player: Spotify.pickPlayer(Mpris.players ? Mpris.players.values : [])
  readonly property bool hasTrack: !!root.player && String(root.player.trackTitle || "").length > 0
  readonly property bool playing: !!root.player && root.player.isPlaying
  readonly property bool controllable: !!root.player && root.player.canControl
  readonly property real length: root.player && root.player.lengthSupported
    ? Math.max(0, Number(root.player.length) || 0) : 0
  readonly property real position: root.player && root.player.positionSupported
    ? Math.max(0, Number(root.player.position) || 0) : 0
  readonly property bool seekable: root.length > 0 && root.controllable
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

  function toggleShuffle() {
    if (root.controllable && root.player.shuffleSupported)
      root.player.shuffle = !root.player.shuffle
  }

  function cycleRepeat() {
    if (!root.controllable || !root.player.loopSupported) return
    root.player.loopState = Spotify.nextLoop(root.player.loopState,
      MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track)
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

  // Every button accepts its click, even when it cannot act, so a dimmed
  // button never falls through to the grid and opens the player instead.
  component TransportControl: Item {
    id: control
    property string glyph: ""
    property real glyphSize: Style.font.icon
    property bool available: true
    property bool lit: false
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
      opacity: !control.available ? 0
        : (controlMouse.containsMouse ? 0.2 : (control.filled ? 0.12 : 0))
    }

    OpticalGlyph {
      anchors.fill: parent
      text: control.glyph
      fontFamily: control.fontFamily
      fontSize: control.glyphSize
      color: control.lit ? Style.selectedStateColor(control.foreground, Color.accent) : control.foreground
      opacity: !control.available ? 0.25 : (control.lit || control.filled ? 1 : 0.7)
    }

    MouseArea {
      id: controlMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: control.available ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (control.available) control.clicked()
    }
  }

  Item {
    id: content
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "SPOTIFY"
      trailing: root.hasTrack ? (root.playing ? "playing" : "paused") : ""
      dotColor: root.playing ? Color.accent : root.foreground
      dotOpacity: root.playing ? 1 : 0.35
      pulse: root.playing
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // Idle: a click anywhere falls through to the grid and opens the player.
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
        text: ""
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2.2)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Nothing playing"
        color: root.foreground
        opacity: 0.8
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Click to open OmaSpotify"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }

    Row {
      id: controls
      visible: root.hasTrack
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Math.max(0, Math.min(Style.space(6),
        Math.floor((content.width - Style.space(28) * 4 - Style.space(32)) / 4)))

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰒟"
        available: root.controllable && root.player.shuffleSupported
        lit: root.hasTrack && root.player.shuffle
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.toggleShuffle()
      }

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰒮"
        available: root.controllable && root.player.canGoPrevious
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.player.previous()
      }

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(32)
        glyph: root.playing ? "󰏤" : "󰐊"
        glyphSize: Style.font.iconLarge
        filled: true
        available: root.controllable && root.player.canTogglePlaying
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.player.togglePlaying()
      }

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "󰒭"
        available: root.controllable && root.player.canGoNext
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.player.next()
      }

      TransportControl {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.hasTrack && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
        available: root.controllable && root.player.loopSupported
        lit: root.hasTrack && root.player.loopState !== MprisLoopState.None
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.cycleRepeat()
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
        text: Spotify.fmtTime(root.position)
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Spotify.fmtTime(root.length)
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Taller than the bar it draws so a click lands without aiming.
    Item {
      id: bar
      visible: times.visible
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: times.top
      height: visible ? Style.space(10) : 0

      Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: barMouse.containsMouse && root.seekable ? Style.space(6) : Style.space(4)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

        Rectangle {
          width: parent.width * Spotify.progress(root.position, root.length)
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
        onClicked: function(mouse) {
          root.seekTo(Spotify.seekTarget(mouse.x, width, root.length))
        }
      }
    }

    // Artwork and text take no clicks, so they open the player through the grid.
    Item {
      id: info
      visible: root.hasTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.bottom: bar.visible ? bar.top : controls.top
      anchors.bottomMargin: Style.space(6)

      Item {
        id: art
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.round(Math.min(info.height, info.width * 0.45)))
        height: width

        Rectangle {
          anchors.fill: parent
          visible: cover.status !== Image.Ready
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

          OpticalGlyph {
            anchors.fill: parent
            text: "󰝚"
            fontFamily: root.fontFamily
            fontSize: Math.max(Style.font.icon, Math.round(parent.height * 0.36))
            color: root.foreground
            opacity: 0.4
          }
        }

        Image {
          id: cover
          anchors.fill: parent
          source: root.hasTrack ? String(root.player.trackArtUrl || "") : ""
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
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.hasTrack ? String(root.player.trackTitle || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text.length > 0
          textFormat: Text.PlainText
          text: root.hasTrack ? String(root.player.trackArtist || "") : ""
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text.length > 0
          textFormat: Text.PlainText
          text: root.hasTrack ? String(root.player.trackAlbum || "") : ""
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
