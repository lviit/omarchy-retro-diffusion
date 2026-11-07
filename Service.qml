import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Polls the Retro Diffusion API through fetch.sh and exposes the parsed,
// validated account summary.
//
// Network access: one HTTPS GET to api.retrodiffusion.ai every
// `refreshIntervalSec` (60s minimum) while `autoRefresh` is on, plus one when
// the panel opens or a refresh is requested. fetch.sh caches the answer for a
// few seconds, so bars on several monitors share a single request.
Item {
  id: root

  property var settings: ({})

  property var info: null
  property string errorKey: ""
  property double updatedAt: 0

  readonly property bool busy: fetchProcess.running
  readonly property bool autoRefresh: setting("autoRefresh", true) !== false
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("fetch.sh")).replace(/^file:\/\//, ""))

  property string _stdout: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.min(max, Math.max(min, n))
  }

  // maxAge: how old (in seconds) a cached answer from another bar may be.
  function refresh(maxAge) {
    if (fetchProcess.running) return
    var age = maxAge === undefined ? 5 : Math.max(0, Math.round(maxAge))
    _stdout = ""
    fetchProcess.command = ["bash", scriptPath, "--max-age", String(age)]
    fetchProcess.running = true
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.autoRefresh
    triggeredOnStart: true
    // Accept another bar's answer from this same tick, but not the last one.
    onTriggered: root.refresh(root.refreshIntervalSec - 10)
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
      onStreamFinished: root._stdout = String(text || "").slice(0, 65536)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorKey = Model.errorKey(exitCode)
        return
      }
      var parsed = Model.parse(String(fetchStdout.text || root._stdout || ""))
      if (!parsed) {
        root.errorKey = "error.unexpected"
        return
      }
      root.info = parsed
      root.errorKey = ""
      root.updatedAt = Date.now()
    }
  }
}
