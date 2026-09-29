import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "repo.js" as Repo

Item {
  id: root
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({ ok: false, branch: "", detached: false, ahead: 0, behind: 0, dirty: 0, untracked: 0, conflicted: 0, hash: "", subject: "", at: 0 })

  readonly property string repoPath: {
    var value = root.tile && root.tile.settings ? String(root.tile.settings.path || "") : ""
    return value || Quickshell.env("HOME") || ""
  }

  function scriptPath(name) {
    var value = Qt.resolvedUrl(name).toString()
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.slice(7))
    return value
  }

  function refresh() {
    if (!root.visible) return
    if (probe.running) {
      probe.again = true
      return
    }
    probe.path = root.repoPath
    probe.command = ["/usr/bin/python3", root.scriptPath("sample.py"), "--path", root.repoPath]
    probe.running = true
  }

  function openLazygit() {
    if (!root.repoPath) return
    // Launch before the launcher closes, like the MLB tile does.
    Util.execArgv(["lazygit", "--path", root.repoPath])
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  Process {
    id: probe
    property bool again: false
    property string path: ""
    command: ["/usr/bin/python3", root.scriptPath("sample.py")]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      if (probe.path !== root.repoPath) {
        probe.again = false
        if (root.visible) Qt.callLater(root.refresh)
        return
      }
      try { root.sample = JSON.parse(probeOut.text || "{}") } catch (e) { }
      if (probe.again) {
        probe.again = false
        Qt.callLater(root.refresh)
        return
      }
      if (root.visible) poll.restart()
    }
  }

  Timer {
    id: poll
    interval: 10000
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()
  onVisibleChanged: if (visible) root.refresh()
  onRepoPathChanged: root.refresh()

  MouseArea {
    z: 0
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.openLazygit()
  }

  Text {
    z: 1
    visible: !root.sample.ok
    anchors.centerIn: parent
    width: parent.width - Style.space(24)
    textFormat: Text.PlainText
    text: "Not a git repo"
    horizontalAlignment: Text.AlignHCenter
    color: root.foreground
    opacity: 0.45
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  Column {
    z: 1
    visible: root.sample.ok
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

    Item {
      width: parent.width
      height: Style.font.caption + 4

      Rectangle {
        id: liveDot
        width: 6
        height: 6
        radius: 3
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: (root.sample.dirty > 0 || root.sample.untracked > 0 || root.sample.conflicted > 0) ? Color.accent : root.foreground
        opacity: (root.sample.dirty > 0 || root.sample.untracked > 0 || root.sample.conflicted > 0) ? 1 : 0.35
      }

      Text {
        anchors.left: liveDot.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "REPO"
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.weight: Font.Medium
        font.letterSpacing: 1
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: Repo.branchLine(root.sample) || "no branch"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: Repo.countsLine(root.sample) !== ""
      textFormat: Text.PlainText
      text: Repo.countsLine(root.sample)
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.sample.hash ? (String(root.sample.hash) + " " + String(root.sample.subject || "")) : "no commits"
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
