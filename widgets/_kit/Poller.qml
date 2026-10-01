import QtQuick
import Quickshell.Io
import "kit.js" as Kit

// Runs a widget's Python sampler and hands back its JSON.
//
//   Poller {
//     script: Qt.resolvedUrl("battery.py")   // resolve it in the widget
//     args: ["--path", root.repoPath]
//     interval: 15000
//     active: root.visible
//     onSampled: function(data) { if (data) root.sample = data }
//   }
//
// It runs when it becomes active, then `interval` ms after each run ends
// (0 runs only on activation and on poll()). A change to `script` or `args`
// throws away a reply still in flight and runs again. `data` is null when the
// sampler printed nothing or bad JSON.
Item {
  id: poller
  visible: false

  property url script
  property var args: []
  property int interval: 10000
  property bool active: true
  // How long pollSoon() waits for an action to land.
  property int settleDelay: 800

  readonly property bool running: proc.running
  readonly property var command: {
    var path = Kit.localPath(poller.script)
    if (!path) return []
    var argv = ["/usr/bin/python3", path]
    var extra = Array.isArray(poller.args) ? poller.args : []
    for (var i = 0; i < extra.length; i++) argv.push(String(extra[i]))
    return argv
  }
  readonly property string commandKey: JSON.stringify(poller.command)

  signal sampled(var data)

  // Run now, or once more right after the run in flight.
  function poll() {
    if (proc.running) inner.again = true
    else inner.start()
  }

  // Run again after an action the widget just took (a toggle, a volume step).
  function pollSoon() {
    settle.restart()
  }

  QtObject {
    id: inner
    property bool ready: false
    property bool again: false
    property string ranKey: ""

    function start() {
      if (poller.command.length === 0) return
      inner.ranKey = poller.commandKey
      proc.command = poller.command
      proc.running = true
    }

    // On activation, a run already in flight is new enough. If its args
    // changed meanwhile, onExited runs again. A Loader shows its item only
    // once it is ready, so a tile becomes active right after it is created;
    // queueing here would sample twice on every open.
    function startIfIdle() {
      if (!proc.running) inner.start()
    }
  }

  onCommandKeyChanged: if (inner.ready && poller.active) inner.startIfIdle()
  onActiveChanged: if (inner.ready && poller.active) inner.startIfIdle()
  Component.onCompleted: {
    inner.ready = true
    if (poller.active) inner.startIfIdle()
  }

  Process {
    id: proc
    // `out.text` is a property. Calling text() throws, and the tile would sit
    // on its defaults forever.
    stdout: StdioCollector { id: out; waitForEnd: true }
    onExited: {
      // `script` or `args` changed while this ran. The reply is for the old ones.
      if (inner.ranKey !== poller.commandKey) {
        inner.again = false
        if (poller.active) Qt.callLater(inner.startIfIdle)
        return
      }
      var data = null
      try { data = JSON.parse(out.text || "") } catch (e) { data = null }
      poller.sampled(data)
      if (inner.again) {
        inner.again = false
        Qt.callLater(inner.startIfIdle)
        return
      }
      if (poller.active && poller.interval > 0) tick.restart()
    }
  }

  Timer {
    id: tick
    interval: Math.max(1, poller.interval)
    onTriggered: if (poller.active) inner.startIfIdle()
  }

  Timer {
    id: settle
    interval: poller.settleDelay
    onTriggered: poller.poll()
  }
}
