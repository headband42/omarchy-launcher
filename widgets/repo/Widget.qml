import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "../_kit/kit.js" as Kit
import "repo.js" as Repo

// One repository at a glance: branch and how far it is from upstream, the
// state of the work tree, two weeks of commits, and the latest few. The
// footer opens lazygit, a terminal, or the folder, and fetches. A click
// anywhere else opens lazygit in the repository.
Item {
  id: root
  clip: true
  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  // The first reply has landed, so "not a repo" is an answer and not a guess.
  property bool loaded: false
  property bool fetching: false
  property string fetchedPath: ""
  property string fetchError: ""
  property real now: Date.now() / 1000

  readonly property string repoPath: {
    var value = root.tile && root.tile.settings ? String(root.tile.settings.path || "") : ""
    return value || Quickshell.env("HOME") || ""
  }
  readonly property var commits: Repo.toList(root.sample && root.sample.commits)
  readonly property var days: Repo.activity(root.sample)
  readonly property int dayPeak: Repo.peak(root.days)
  readonly property var chipList: Repo.chips(root.sample)
  readonly property string treeState: Repo.state(root.sample)
  readonly property bool ok: root.loaded && !!(root.sample && root.sample.ok)
  readonly property int ahead: root.ok ? Math.max(0, Number(root.sample.ahead) || 0) : 0
  readonly property int behind: root.ok ? Math.max(0, Number(root.sample.behind) || 0) : 0
  readonly property bool tracking: root.ok && String(root.sample.upstream || "").length > 0

  readonly property color upTone: Color.accent
  readonly property color downTone: Qt.rgba(0.36, 0.62, 0.86, 1)

  function launch(argv) {
    // Launch before the launcher closes, like the MLB tile does.
    Util.execArgv(argv)
    if (root.host && root.host.dismiss) root.host.dismiss()
  }

  // lazygit is a TUI, so it needs a terminal window of its own.
  function openLazygit() {
    if (root.repoPath) root.launch(["omarchy-launch-tui", "lazygit", "--path", root.repoPath])
  }

  function openTerminal() {
    if (root.ok && root.host && root.host.openTerminal) root.host.openTerminal(String(root.sample.path || root.repoPath))
  }

  function openFolder() {
    if (root.ok && root.host && root.host.openFolder) root.host.openFolder(String(root.sample.path || root.repoPath))
  }

  function fetch() {
    if (root.fetching || !root.tracking) return
    root.fetching = true
    root.fetchError = ""
    root.fetchedPath = root.repoPath
    fetcher.command = ["/usr/bin/python3", Kit.localPath(Qt.resolvedUrl("repo.py")), "--path", root.repoPath, "--fetch"]
    fetcher.running = true
  }

  function chipFill(tone) {
    if (tone === "urgent") return Util.alpha(Color.urgent, 0.38)
    if (tone === "accent") return Util.alpha(Color.accent, 0.26)
    if (tone === "clean") return Util.alpha(Color.accent, 0.14)
    if (tone === "muted") return Util.alpha(root.foreground, 0.05)
    return Util.alpha(root.foreground, 0.10)
  }

  onRepoPathChanged: {
    root.loaded = false
    root.fetchError = ""
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("repo.py")
    args: ["--path", root.repoPath]
    interval: 10000
    active: root.visible
    onSampled: function(data) {
      if (!data) return
      root.sample = data
      root.loaded = true
      root.now = Date.now() / 1000
    }
  }

  Process {
    id: fetcher
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    onExited: {
      root.fetching = false
      // The tile moved to another repository while this ran.
      if (root.fetchedPath !== root.repoPath) return
      var data = null
      try { data = JSON.parse(fetchOut.text || "") } catch (e) { data = null }
      if (data && data.ok) {
        root.sample = data
        root.loaded = true
      }
      var result = data && data.fetch
      root.fetchError = !data ? "fetch failed" : (result && !result.ok ? String(result.error || "fetch failed") : "")
      root.now = Date.now() / 1000
    }
  }

  // Ages tick over while the launcher stays open.
  Timer {
    interval: 30000
    repeat: true
    running: root.visible
    onTriggered: root.now = Date.now() / 1000
  }

  MouseArea {
    z: 0
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.openLazygit()
  }

  TextMetrics {
    id: hashMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "0000000"
  }

  TextMetrics {
    id: ageMetric
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "00mo"
  }

  Item {
    id: content
    z: 1
    anchors.fill: parent
    anchors.margins: Style.space(12)

    WidgetHeader {
      id: header
      title: "REPO"
      trailing: root.ok ? String(root.sample.name || "") : ""
      dotColor: root.treeState === "conflict" ? Color.urgent
        : (root.treeState === "dirty" ? Color.accent : root.foreground)
      dotOpacity: root.treeState === "conflict" || root.treeState === "dirty" ? 1 : 0.35
      pulse: root.fetching
      fontFamily: root.fontFamily
      foreground: root.foreground
    }

    // Not a repository, or a path that is gone.
    Column {
      visible: root.loaded && !root.ok
      anchors.centerIn: parent
      width: parent.width
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: ""
        color: root.foreground
        opacity: 0.25
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge * 2
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Not a git repository"
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Repo.displayPath(root.repoPath, Quickshell.env("HOME"))
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Pick one with the gear"
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: branchRow
      visible: root.ok
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.max(branchName.implicitHeight, pills.height)

      Text {
        id: branchGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: ""
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: branchName
        anchors.left: branchGlyph.right
        anchors.leftMargin: Style.space(6)
        anchors.right: pills.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Repo.branchLine(root.sample) || "no branch"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      Row {
        id: pills
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Repeater {
          model: [
            { glyph: "", count: root.ahead, tone: root.upTone },
            { glyph: "", count: root.behind, tone: root.downTone }
          ]

          Rectangle {
            required property var modelData
            visible: modelData.count > 0
            radius: height / 2
            color: Util.alpha(modelData.tone, 0.24)
            implicitWidth: pillText.implicitWidth + Style.space(12)
            implicitHeight: pillText.implicitHeight + Style.space(4)

            Text {
              id: pillText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: modelData.glyph + " " + modelData.count
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.features: ({ "tnum": 1 })
            }
          }
        }
      }
    }

    Text {
      id: upstreamText
      visible: root.ok
      anchors.top: branchRow.bottom
      anchors.topMargin: Style.space(1)
      anchors.left: parent.left
      anchors.leftMargin: branchName.x
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: Repo.upstreamLine(root.sample)
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Flow {
      id: chipFlow
      visible: root.ok
      anchors.top: upstreamText.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(4)

      Repeater {
        model: root.chipList

        Rectangle {
          required property var modelData
          radius: height / 2
          color: root.chipFill(modelData.tone)
          implicitWidth: chipText.implicitWidth + Style.space(14)
          implicitHeight: chipText.implicitHeight + Style.space(5)

          Text {
            id: chipText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: (modelData.key === "clean" ? " " : (modelData.key === "stash" ? " " : ""))
              + modelData.label
            color: root.foreground
            opacity: modelData.tone === "muted" ? 0.7 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    // Two weeks of commits, a bar a day, today on the right.
    Item {
      id: activity
      visible: root.ok
      anchors.top: chipFlow.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      height: bars.height + Style.space(3) + activityCaption.height

      Row {
        id: bars
        width: parent.width
        height: Style.space(22)
        spacing: Style.space(3)

        Repeater {
          model: root.days.length

          Item {
            required property int index
            readonly property int commitsThatDay: root.days[index] || 0
            readonly property real level: Repo.barLevel(commitsThatDay, root.dayPeak)
            width: (bars.width - bars.spacing * (root.days.length - 1)) / root.days.length
            height: bars.height

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: parent.commitsThatDay > 0 ? Math.max(Style.space(3), Math.round(parent.height * parent.level)) : Style.space(2)
              radius: Math.min(width / 2, Style.space(2))
              color: parent.commitsThatDay > 0 ? Color.accent : root.foreground
              opacity: parent.commitsThatDay > 0 ? 0.4 + 0.6 * parent.level : 0.14
            }
          }
        }
      }

      Item {
        id: activityCaption
        anchors.top: bars.bottom
        anchors.topMargin: Style.space(3)
        width: parent.width
        height: twoWeeks.implicitHeight

        Text {
          id: twoWeeks
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: "2 weeks"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: Repo.total(root.days) === 1 ? "1 commit" : Repo.total(root.days) + " commits"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // The latest commits, as many as fit. Unpushed ones carry the accent.
    Item {
      id: log
      visible: root.ok
      anchors.top: activity.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(4)

      readonly property int rowHeight: Style.font.bodySmall + Style.space(7)
      readonly property int rows: Math.max(0, Math.min(root.commits.length, Math.floor(log.height / log.rowHeight)))

      Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: root.foreground
        opacity: 0.08
      }

      Text {
        visible: root.commits.length === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "No commits yet"
        color: root.foreground
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Column {
        y: Style.space(4)
        width: parent.width

        Repeater {
          model: log.rows

          Item {
            required property int index
            readonly property var commit: root.commits[index] || ({})
            readonly property bool unpushed: Repo.unpushed(root.sample, index)
            width: log.width
            height: log.rowHeight

            Text {
              id: hashText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.ceil(hashMetric.advanceWidth)
              textFormat: Text.PlainText
              text: String(parent.commit.hash || "")
              color: parent.unpushed ? Color.accent : root.foreground
              opacity: parent.unpushed ? 0.95 : 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.features: ({ "tnum": 1 })
            }

            Text {
              anchors.left: hashText.right
              anchors.leftMargin: Style.space(8)
              anchors.right: ageText.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(parent.commit.subject || "")
              color: root.foreground
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: ageText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.ceil(ageMetric.advanceWidth)
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Repo.ageLabel(parent.commit.at, root.now)
              color: root.foreground
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    Item {
      id: footer
      visible: root.ok
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(24)

      Row {
        id: buttons
        anchors.left: parent.left
        anchors.leftMargin: -Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        IconButton {
          glyph: ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openLazygit()
        }

        IconButton {
          glyph: ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openTerminal()
        }

        IconButton {
          glyph: ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openFolder()
        }

        IconButton {
          visible: root.tracking
          glyph: ""
          busy: root.fetching
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.fetch()
        }
      }

      Text {
        anchors.left: buttons.right
        anchors.leftMargin: Style.space(6)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: root.fetching ? "fetching…" : (root.fetchError || Repo.fetchedLine(root.sample, root.now))
        color: root.fetchError && !root.fetching ? Color.urgent : root.foreground
        opacity: root.fetchError && !root.fetching ? 0.9 : 0.4
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
