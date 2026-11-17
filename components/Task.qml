import QtQuick
import Quickshell.Io

// Runs a program once and reports its exit code and both outputs together.
// Input goes in through `sh` instead of the process's stdin, so the program
// always sees it end, and a missing program reports 127 like any failure.
Item {
  id: task

  property var job: null
  readonly property bool busy: proc.running || pendingParts > 0

  property int pendingParts: 0
  property int exitCode: 0
  property bool exited: false
  property string out: ""
  property string err: ""

  signal done(int exitCode, string output, string errorOutput, var job)

  function start(argv, options) {
    var o = options || {}
    job = o.job === undefined ? null : o.job
    out = ""
    err = ""
    exitCode = 0
    exited = false
    pendingParts = 3
    var feed = typeof o.input === "string"
      ? ["sh", "-c", 'printf %s "$1" | { shift; exec "$@"; }', "omarclip-task", o.input]
      : ["sh", "-c", 'shift; exec "$@"', "omarclip-task", ""]
    proc.command = feed.concat(argv)
    proc.running = true
  }

  function partDone() {
    if (pendingParts <= 0) return
    pendingParts -= 1
    if (exited && pendingParts > 0) streamsTimeout.restart()
    if (pendingParts === 0) {
      streamsTimeout.stop()
      done(exitCode, out, err, job)
    }
  }

  Process {
    id: proc

    stdout: StdioCollector {
      onStreamFinished: { task.out = text; task.partDone() }
    }
    stderr: StdioCollector {
      onStreamFinished: { task.err = text; task.partDone() }
    }
    onExited: function(code) {
      task.exitCode = code
      task.exited = true
      task.partDone()
    }
  }

  // A background child that inherited the output can keep it open; the
  // result doesn't wait for it once the program itself is gone.
  Timer {
    id: streamsTimeout
    interval: 2000
    onTriggered: {
      while (task.pendingParts > 0) task.partDone()
    }
  }
}
