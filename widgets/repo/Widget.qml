import QtQuick
import Quickshell
import qs.Commons
import "../_kit"
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

  function openLazygit() {
    if (!root.repoPath) return
    // Launch before the launcher closes, like the MLB tile does.
    Util.execArgv(["lazygit", "--path", root.repoPath])
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("repo.py")
    args: ["--path", root.repoPath]
    interval: 10000
    active: root.visible
    onSampled: function(data) { if (data) root.sample = data }
  }

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

    WidgetHeader {
      title: "REPO"
      dotColor: (root.sample.dirty > 0 || root.sample.untracked > 0 || root.sample.conflicted > 0) ? Color.accent : root.foreground
      dotOpacity: (root.sample.dirty > 0 || root.sample.untracked > 0 || root.sample.conflicted > 0) ? 1 : 0.35
      fontFamily: root.fontFamily
      foreground: root.foreground
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
