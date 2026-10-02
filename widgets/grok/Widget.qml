import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../_kit"
import "../_kit/usage.js" as Usage
import "grok.js" as Grok

// Your Grok plan's limits: the fullest one as a big number, then a bar for
// the weekly or monthly allowance, for Grok Build and Grok Chat when they
// split it, and for pay-as-you-go when a spending cap is set. Read from the
// sign-in Grok already has. The last good reply is drawn from the cache
// while the first poll of a session is out. A click falls through to the
// slot's Opens, grok.com's usage page by default.
Item {
  id: root
  clip: true

  property var tile: ({})
  property var host: ({})
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property var sample: ({})
  // A reply from grok.py this session, not the cache.
  property bool live: false
  // The last poll failed after a good one, so the numbers are old.
  property bool offline: false
  property real now: Date.now()

  readonly property var settings: root.tile && root.tile.settings ? root.tile.settings : ({})
  readonly property string resetStyle: String(root.settings.resetStyle || "relative")
  readonly property bool haveData: !!(root.sample && root.sample.ok)
  readonly property var meters: Usage.visibleMeters(root.haveData ? root.sample.meters : [], root.settings.hidden)
  readonly property bool stale: root.haveData && (root.offline || !root.live)
  readonly property var rows: root.meters.map(function(meter) {
    return {
      label: Grok.label(meter),
      percent: meter.percent,
      over: !!meter.over,
      detail: Grok.detailLine(meter, Usage.resetLine(meter.resetsAtMs, root.now, root.resetStyle)),
      caption: String(meter.caption || "")
    }
  })
  readonly property string cachePath: {
    var base = String(Quickshell.env("XDG_CACHE_HOME") || "")
    if (!base) base = String(Quickshell.env("HOME") || "") + "/.cache"
    return base + "/ande.launcher/grok.json"
  }

  function apply(data) {
    root.now = Date.now()
    if (data && data.ok) {
      root.sample = data
      root.live = true
      root.offline = false
      return
    }
    // A failure after a good read keeps the numbers but says they are old.
    if (root.haveData) {
      root.offline = true
      return
    }
    root.sample = data || { ok: false, reason: "error", error: "Grok usage is unavailable", meters: [] }
    root.live = true
  }

  Poller {
    id: poller
    script: Qt.resolvedUrl("grok.py")
    interval: Math.max(30000, Math.min(900000, Number(root.sample && root.sample.pollMs) || 300000))
    active: root.visible
    onSampled: function(data) { root.apply(data) }
  }

  FileView {
    path: root.cachePath
    printErrors: false
    watchChanges: false
    onLoaded: {
      if (root.live) return
      var cached = Grok.fromCache(text())
      if (cached) {
        root.sample = cached
        root.now = Date.now()
      }
    }
  }

  // Countdowns tick between polls.
  Timer {
    interval: 30000
    repeat: true
    running: root.visible
    onTriggered: root.now = Date.now()
  }

  UsageBoard {
    anchors.fill: parent
    title: Grok.planLabel(root.sample)
    rows: root.rows
    footer: Grok.footerLine(root.sample)
    footnote: root.stale ? Usage.ageLine(root.sample.savedAt, root.now) : ""
    stale: root.offline
    busy: Number(root.sample && root.sample.pollMs) > 0 && Number(root.sample.pollMs) < 300000
    emptyHeadline: root.haveData ? "Every limit is hidden" : Grok.emptyHeadline(root.live ? root.sample : null)
    emptyBody: root.haveData ? "Show one with the gear." : Grok.emptyBody(root.live ? root.sample : null)
    fontFamily: root.fontFamily
    foreground: root.foreground
  }
}
