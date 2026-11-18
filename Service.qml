import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "components"
import "lib/Config.js" as Config
import "lib/Recorder.js" as Recorder
import "lib/Hotkeys.js" as Hotkeys
import "lib/Glyphs.js" as Glyphs

// Omarclip's headless half: the replay buffer, saving clips and the global
// hotkeys. The panel, the bar widget and IPC all drive this one object.
//
// The buffer is gpu-screen-recorder in replay mode (bin/omarclip-recorder):
// it keeps the last `length` seconds encoded at constant bitrate, in RAM by
// default, and writes them to a file only when asked over its IPC socket
// (bin/omarclip-save). Saving does not interrupt it, so you can save again
// right away, and the next clip overlaps the last one, like ShadowPlay.
Item {
  id: root
  visible: false

  // Host injection (see the Omarchy shell README).
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.gelzinn.omarclip"
  // Global shortcut namespace and runtime folder. The dev host uses its own
  // and runs without hotkeys, so it never competes with the installed plugin.
  property string appId: "omarclip"
  property bool hotkeysEnabled: true
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string home: Quickshell.env("HOME")
  // Named after appId, so a dev instance keeps its own settings and never
  // restarts the installed buffer by writing to its config.
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/" + appId
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/" + appId
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/" + appId
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/" + appId
  readonly property string socketPath: runtimeDir + "/gsr.sock"
  // Omarchy requires every Lua file in this folder on each Hyprland reload,
  // which is what keeps the hotkeys bound across reloads and logins.
  readonly property string bindsPath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/toggles/hypr/" + appId + ".lua"
  readonly property string shellJsonPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/shell.json"
  // Every bind Omarclip makes is described with this prefix, which is how it
  // tells its binds apart from the user's (the dev host gets its own).
  readonly property string bindPrefix: appId === "omarclip" ? "Omarclip: " : "Omarclip (" + appId + "): "

  property var config: Config.defaults()
  property bool ready: false
  property var appState: ({})

  // off       the buffer is switched off
  // starting  the recorder is coming up
  // running   recording into the buffer
  // waiting   no screen to record (monitors asleep or unplugged); retrying
  // error     the recorder failed; retrying with a growing delay
  property string status: "off"
  property string statusDetail: ""
  readonly property bool running: status === "running"
  // When the buffer started filling: a save before it is full keeps less.
  property double bufferStartedAt: 0
  property string recordingMonitor: ""
  // The recorded monitor's size, for the quality estimate (0: not known yet).
  property int monitorWidth: 0
  property int monitorHeight: 0
  readonly property double bufferBytes: Recorder.bufferBytes(config, monitorWidth, monitorHeight)

  property bool saving: false
  property var lastClip: null
  signal clipSaved(var clip)

  property bool panelOpen: false
  property string notice: ""
  property string noticeKind: "info"

  readonly property string shortcutsKey: JSON.stringify(computeShortcuts(config))
  readonly property var shortcuts: JSON.parse(shortcutsKey)

  function log(message) { console.info("omarclip: " + message) }
  function warn(message) { console.warn("omarclip: " + message) }

  // Inline in the panel when it is open, a desktop notification otherwise.
  // action: the report answers a save you just asked for (see notify).
  function report(text, kind, action) {
    var level = kind || "error"
    if (level === "error") warn(text)
    else log(text)
    notice = text
    noticeKind = level
    noticeTimer.restart()
    if (!panelOpen && level === "error") notify("Omarclip", text, { glyph: Glyphs.off, urgency: "critical", action: action === true })
  }

  // options: { glyph, image, open, urgency, action }
  // action: the answer to something you just did (a hotkey, a click). It goes
  // out as Omarchy's own "omarchy-action", like its screenshot and recording
  // notices, so Do Not Disturb lets it through.
  function notify(title, body, options) {
    var o = options || {}
    var args = ["--app-name", o.action ? "omarchy-action" : "Omarclip", "-g", o.glyph || Glyphs.app]
    if (o.urgency) args.push("-u", o.urgency)
    if (o.image) args.push("--image", o.image)
    args.push(title, body || "")
    // Clicking the notification opens the clip.
    if (o.open) args.push("--exec", "xdg-open", o.open)
    Quickshell.execDetached(["sh", "-c",
      'title=$1 body=$2; shift 2; '
      + 'if command -v omarchy-notification-send >/dev/null; then exec omarchy-notification-send "$@"; fi; '
      + 'exec notify-send -a Omarclip "$title" "$body"', "omarclip-notify", String(title), String(body || "")]
      .concat(args.map(String)))
  }

  Timer {
    id: noticeTimer
    interval: 4500
    onTriggered: root.notice = ""
  }

  Component.onCompleted: {
    log("starting from " + pluginDir)
    initProc.exec(["bash", "-c", 'umask 077 && mkdir -p -- "$@" && chmod 700 -- "$@"', "omarclip-init",
      configDir, stateDir, cacheDir])
  }

  // Runs detached once the shell is done with this object. A reload or a
  // shell restart leaves Omarclip listed in shell.json, and the next instance
  // takes over the hotkeys and the recorder. Disabling or removing the plugin
  // takes it out, and then its hotkeys and its recorder go too. Inline,
  // because `plugin remove` deletes the plugin folder.
  readonly property string cleanupScript: [
    "sleep 1",
    "shell_json=$1 binds=$2 state_dir=$3 prefix=$4 id=$5 runtime_dir=$6 pid=$7 owned_awk=$8 listed_jq=$9",
    "if [[ -f $shell_json ]] && jq -e --arg id \"$id\" \"$listed_jq\" \"$shell_json\" >/dev/null 2>&1; then exit 0; fi",
    "rm -f \"$binds\" \"$state_dir/state.json\"",
    // Unbinding goes by key, so only keys Hyprland shows bound to us and to
    // nothing else, read now. If the binds can't be read, nothing is unbound;
    // the binds file is gone, so the next Hyprland reload drops ours anyway.
    "if listing=$(hyprctl binds 2>/dev/null); then",
    "  lua=''",
    "  while IFS= read -r key; do",
    "    [[ $key =~ ^((SUPER|CTRL|ALT|SHIFT)\\ \\+\\ )*code:[0-9]{1,3}$ ]] && lua+=\"pcall(hl.unbind, \\\"$key\\\")\"$'\\n'",
    "  done < <(awk -v prefix=\"$prefix\" \"$owned_awk\" <<<\"$listing\")",
    "  [[ -n $lua ]] && hyprctl eval \"$lua\" >/dev/null 2>&1",
    "fi",
    // This instance's own recorder only, by the pid it had: a newer instance
    // may already have started another one.
    "if [[ $pid =~ ^[1-9][0-9]*$ && $(readlink \"/proc/$pid/exe\" 2>/dev/null) == */omarclip-gsr* ]]; then kill -INT \"$pid\"; fi",
    "current=$(cat \"$runtime_dir/recorder.pid\" 2>/dev/null)",
    "if [[ ( -z $current || $current == \"$pid\" ) && -d $runtime_dir && ! -L $runtime_dir && -O $runtime_dir ]]; then rm -rf \"$runtime_dir\"; fi"
  ].join("\n")

  Component.onDestruction: {
    log("shutting down")
    stopping = true
    try {
      Quickshell.execDetached(["bash", "-c", cleanupScript, "omarclip-cleanup",
        shellJsonPath, bindsPath, stateDir, bindPrefix, pluginId, runtimeDir,
        recorderProc.running ? recorderProc.processId : 0, Hotkeys.OWNED_KEYS_AWK, Config.SHELL_LISTED_JQ].map(String))
    } catch (e) {
      warn("cleanup did not start: " + e)
    }
    // A reload starts the next instance's recorder from scratch; this one stops now.
    if (recorderProc.running) recorderProc.signal(2)
  }

  Process {
    id: initProc
    onExited: stateFile.path = root.stateDir + "/state.json"
  }

  FileView {
    id: stateFile
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object") root.appState = parsed
      } catch (e) {
        root.warn("ignoring unreadable state.json: " + e)
      }
      root.loadConfig()
    }
    onLoadFailed: root.loadConfig()
  }

  function saveState(patch) {
    var next = JSON.parse(JSON.stringify(appState || {}))
    for (var key in patch) next[key] = patch[key]
    appState = next
    stateFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function loadConfig() {
    if (configFile.path === "") configFile.path = configDir + "/config.json"
  }

  FileView {
    id: configFile
    printErrors: false
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadConfigText(text())
    onLoadFailed: function(error) {
      if (root.ready) return
      if (error === FileViewError.FileNotFound) {
        root.applyConfig(Config.defaults(), true)
        return
      }
      root.configBroken = true
      root.report("Could not read config.json (" + FileViewError.toString(error) + "); replay and audio stay off until it is fixed")
      root.applyConfig(Config.fallback(), false)
    }
    // Editors and shell redirects write in steps; read once they settle.
    onFileChanged: configReloadTimer.restart()
  }

  Timer {
    id: configReloadTimer
    interval: 250
    onTriggered: configFile.reload()
  }

  property string configText: ""
  // config.json exists but does not parse. Until it is fixed nothing is
  // written to it, so the user's settings are never replaced by defaults.
  property bool configBroken: false

  function loadConfigText(text) {
    var raw = String(text || "")
    if (ready && raw === configText) return
    var parsed
    var problem = ""
    try {
      parsed = JSON.parse(raw)
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) problem = "is not a JSON object"
    } catch (e) {
      problem = "is not valid JSON (" + e + ")"
    }
    if (problem) {
      configBroken = true
      if (!ready) {
        report("config.json " + problem + "; replay and audio stay off until it is fixed")
        applyConfig(Config.fallback(), false)
      } else {
        report("config.json " + problem + "; keeping the previous settings until it is fixed")
      }
      return
    }
    if (configBroken) log("config.json is valid again")
    configBroken = false
    applyConfig(Config.normalize(parsed), false)
  }

  // Adopts a config and runs whatever its changes require. `save` writes it
  // back; edits made to the file by hand arrive here with save = false.
  function applyConfig(next, save) {
    var previous = config
    var wasReady = ready
    config = next
    configText = JSON.stringify(next, null, 2) + "\n"
    if (save && !configBroken) configFile.setText(configText)
    if (!wasReady) {
      ready = true
      syncBinds()
      syncRecorder(false)
      return
    }
    if (JSON.stringify(previous.hotkeys) !== JSON.stringify(next.hotkeys)) syncBinds()
    if (previous.enabled !== next.enabled) syncRecorder(false)
    else if (next.enabled && Recorder.needsRestart(previous, next)) {
      // Sliders and arrow keys change settings in quick steps; restart once
      // they settle, since every restart empties the buffer.
      restartDebounce.restart()
    }
  }

  function setSetting(key, value) {
    if (!ready) return
    applyConfig(Config.withSetting(config, key, value), true)
  }

  property bool stopping: false
  // A restart asked for while the recorder was still running.
  property bool restartPending: false
  property int failures: 0
  property var recorderErrors: []

  Timer {
    id: restartDebounce
    interval: 1200
    onTriggered: root.syncRecorder(true)
  }

  // Brings the recorder in line with config.enabled; `restart` also
  // replaces a running one (settings changed).
  function syncRecorder(restart) {
    if (!ready || stopping) return
    retryTimer.stop()
    if (!config.enabled) {
      restartPending = false
      if (recorderProc.running) recorderProc.signal(2)
      else setStatus("off", "")
      return
    }
    if (recorderProc.running || monitorsProc.busy) {
      if (restart && recorderProc.running) {
        restartPending = true
        recorderProc.signal(2)
      }
      return
    }
    failures = restart ? 0 : failures
    setStatus("starting", "")
    monitorsProc.start(["hyprctl", "monitors", "-j"])
  }

  function setStatus(next, detail) {
    if (status !== next) log("buffer: " + next + (detail ? " (" + detail + ")" : ""))
    status = next
    statusDetail = detail || ""
  }

  // The monitor to record: the one named in the config, or the focused one.
  Task {
    id: monitorsProc
    onDone: function(exitCode, output) {
      if (!root.config.enabled || root.stopping) {
        root.setStatus("off", "")
        return
      }
      var monitors = []
      try { monitors = JSON.parse(output) } catch (e) { monitors = [] }
      if (!Array.isArray(monitors)) monitors = []
      var awake = monitors.filter(function(m) { return m && !m.disabled && m.dpmsStatus !== false })
      var wanted = root.config.monitor
      var pick = null
      for (var i = 0; i < awake.length; i++) if (wanted !== "focused" && awake[i].name === wanted) pick = awake[i]
      if (!pick && wanted !== "focused") {
        var known = monitors.some(function(m) { return m && m.name === wanted })
        root.waitForScreen(known ? wanted + " is asleep" : wanted + " is not connected")
        return
      }
      for (var j = 0; !pick && j < awake.length; j++) if (awake[j].focused) pick = awake[j]
      if (!pick && awake.length > 0) pick = awake[0]
      if (!pick) {
        root.waitForScreen(monitors.length > 0 ? "Screens are asleep" : "No screen found")
        return
      }
      root.monitorWidth = Number(pick.width) || 0
      root.monitorHeight = Number(pick.height) || 0
      root.startRecorder(pick.name, Number(pick.height) || 0)
    }
  }

  function expandHome(path) {
    return String(path || "").replace(/^~(?=\/|$)/, home)
  }

  readonly property string outputDir: expandHome(config.folder)

  function startRecorder(monitorName, nativeHeight) {
    var argv = Recorder.args(config, { monitor: monitorName, socket: socketPath, output: outputDir, nativeWidth: monitorWidth, nativeHeight: nativeHeight })
    recordingMonitor = monitorName
    recorderErrors = []
    recorderProc.startedAt = Date.now()
    recorderProc.command = [pluginDir + "/bin/omarclip-recorder", runtimeDir, cacheDir, outputDir, "--"].concat(argv)
    recorderProc.running = true
    log("recording " + monitorName + " · " + Config.formatLength(config.length) + " · "
      + Config.resolutionLabel(config.resolution) + " " + config.fps + " fps " + Recorder.bitrateFor(config, monitorWidth, monitorHeight) + " Mbps" + (config.bitrate === "auto" ? " (auto) " : " ") + config.codec)
  }

  // Nothing to record right now. Not an error: monitors sleep. Check again
  // every few seconds, and come back as soon as one wakes up.
  function waitForScreen(reason) {
    setStatus("waiting", reason)
    retryTimer.interval = 4000
    retryTimer.restart()
  }

  Timer {
    id: retryTimer
    onTriggered: root.syncRecorder(false)
  }

  // The recorder becomes "running" once its socket answers: a recorder that
  // dies at startup (bad monitor, codec the GPU lacks) never counts.
  Timer {
    id: readyCheck
    interval: 700
    repeat: true
    running: root.status === "starting" && recorderProc.running
    onTriggered: if (!probeProc.busy) probeProc.start(["gsr-cli", "-ipc", root.socketPath, "status"])
  }

  Task {
    id: probeProc
    onDone: function(exitCode) {
      if (exitCode !== 0 || root.status !== "starting" || !recorderProc.running) return
      root.bufferStartedAt = Date.now()
      root.setStatus("running", root.recordingMonitor)
      if (root.failures > 0) root.log("recorder is back after " + root.failures + " failed starts")
    }
  }

  // Failure streaks end once a recorder stays up for a while.
  Timer {
    interval: 30000
    running: root.running
    onTriggered: root.failures = 0
  }

  Process {
    id: recorderProc
    property double startedAt: 0

    stderr: SplitParser {
      onRead: function(line) {
        var text = String(line).trim()
        if (!text) return
        var list = root.recorderErrors.concat([text])
        root.recorderErrors = list.slice(-6)
      }
    }

    onExited: function(exitCode) {
      root.bufferStartedAt = 0
      if (root.stopping) return
      if (root.restartPending || !root.config.enabled) {
        root.restartPending = false
        if (root.config.enabled) root.syncRecorder(false)
        else root.setStatus("off", "")
        return
      }
      root.recorderFailed(exitCode)
    }
  }

  function recorderFailed(exitCode) {
    var errors = recorderErrors.filter(function(l) { return /error|failed|not found|unsupported|cannot|could not/i.test(l) })
    var reason = errors.length ? errors[errors.length - 1] : (recorderErrors.length ? recorderErrors[recorderErrors.length - 1] : "exit " + exitCode)
    reason = reason.replace(/^gsr (error|info|warning):\s*/i, "")
    // Monitors went to sleep or were unplugged under the recorder.
    if (/display .* not found|no usable output|failed to find the gpu that the monitor/i.test(reason)) {
      waitForScreen("Screens are asleep")
      return
    }
    failures++
    var delay = Math.min(60, Math.pow(2, failures)) * 1000
    setStatus("error", reason)
    // Once per streak, so a broken setup is not a stream of notifications.
    if (failures === 1) report("Replay buffer stopped: " + reason)
    retryTimer.interval = delay
    retryTimer.restart()
  }

  function setEnabled(on) {
    setSetting("enabled", on === true)
  }

  function toggleEnabled() {
    setEnabled(!config.enabled)
    notify(config.enabled ? "Instant replay on" : "Instant replay off",
      config.enabled ? "Keeping the last " + Config.formatLength(config.length) : "",
      { glyph: config.enabled ? Glyphs.app : Glyphs.off, action: true })
  }

  // Seconds the buffer holds right now: it fills from zero after each start.
  function bufferedSeconds() {
    if (!running || !bufferStartedAt) return 0
    return Math.min(config.length, Math.floor((Date.now() - bufferStartedAt) / 1000))
  }

  // seconds: how far back from now; defaults to the replay length.
  function saveClip(seconds) {
    if (saving) return false
    if (!config.enabled) {
      report("Instant replay is off. Turn it on with " + (config.hotkeys.toggle ? config.hotkeys.toggle.label : "the panel") + ".", "error", true)
      return false
    }
    if (!running) {
      report(status === "waiting" ? "Nothing to save. " + statusDetail
        : status === "error" ? "Nothing to save: the replay buffer stopped (" + statusDetail + ")"
        : "The replay buffer is still starting", "error", true)
      return false
    }
    var wanted = Math.round(Number(seconds) || config.length)
    wanted = Math.max(1, Math.min(config.length, wanted))
    saving = true
    saveProc.start([pluginDir + "/bin/omarclip-save"], {
      job: { seconds: wanted, pressedAt: Date.now() },
      input: JSON.stringify({ socket: socketPath, seconds: wanted })
    })
    return true
  }

  Task {
    id: saveProc
    onDone: function(exitCode, output, errorOutput, job) {
      var reply = null
      try { reply = JSON.parse(String(output || "").trim().split("\n").pop()) } catch (e) { reply = null }
      if (!reply || !reply.ok) {
        root.saving = false
        root.report("Could not save the clip: " + (reply && reply.error ? reply.error : String(errorOutput || "exit " + exitCode).trim()), "error", true)
        return
      }
      var app = Recorder.appName(reply.class, reply.title)
      var stamp = Qt.formatDateTime(new Date(job.pressedAt), "yyyy-MM-dd HH-mm-ss")
      var name = Recorder.safeName(app + " " + stamp, "Clip " + stamp)
      fileProc.start([root.pluginDir + "/bin/omarclip-file"], {
        job: { app: app, seconds: job.seconds, savedAt: Date.now() },
        input: JSON.stringify({
          path: reply.path,
          dir: root.config.organizeByApp ? root.outputDir + "/" + app : root.outputDir,
          name: name,
          thumbs: root.cacheDir + "/thumbs"
        })
      })
    }
  }

  Task {
    id: fileProc
    onDone: function(exitCode, output, errorOutput, job) {
      root.saving = false
      var reply = null
      try { reply = JSON.parse(String(output || "").trim().split("\n").pop()) } catch (e) { reply = null }
      if (!reply || !reply.path) {
        var why = String(errorOutput || "").trim().split("\n").pop().replace(/^omarclip-file: /, "")
        root.report("Could not save the clip: " + (why || "exit " + exitCode), "error", true)
        return
      }
      var held = Math.min(job.seconds, root.bufferedSeconds() || job.seconds)
      var clip = { path: reply.path, thumb: reply.thumb || "", app: job.app, seconds: held, savedAt: job.savedAt }
      root.lastClip = clip
      root.clipSaved(clip)
      root.log("saved " + reply.path)
      if (root.config.notify) {
        root.notify("Clip saved", job.app + " · " + Config.formatLength(held) + " · " + reply.path.split("/").pop(),
          { glyph: Glyphs.saved, image: reply.thumb, open: reply.path, action: true })
      }
      // The recorder's file is the clip either way; filing it is a tidy-up.
      if (reply.filed === false) root.report("Saved, but it could not be moved to the clips folder; it is at " + reply.path, "info")
      else if (root.panelOpen) root.report("Saved " + reply.path.split("/").pop(), "info")
    }
  }

  function openFolder() {
    Quickshell.execDetached(["bash", "-c", 'mkdir -p -- "$1" && exec xdg-open "$1"', "omarclip-open", outputDir])
  }

  function openLastClip() {
    if (lastClip && lastClip.path) Quickshell.execDetached(["xdg-open", lastClip.path])
  }

  readonly property var actionLabels: ({ save: "Save clip", toggle: "Turn instant replay on/off", open: "Open Omarclip" })

  function computeShortcuts(cfg) {
    return ["save", "toggle", "open"].filter(function(action) { return !!cfg.hotkeys[action] }).map(function(action) {
      var hk = cfg.hotkeys[action]
      return { name: action, keys: hk.keys, label: hk.label, description: bindPrefix + actionLabels[action].toLowerCase() }
    })
  }

  // While a key is briefly bound twice (a reload taking over), one press
  // arrives twice in the same instant.
  property var pressedAt: ({})

  function onShortcut(action) {
    var now = Date.now()
    if (now - (pressedAt[action] || 0) < 250) return
    pressedAt[action] = now
    if (action === "save") saveClip(0)
    else if (action === "toggle") toggleEnabled()
    else togglePanel()
  }

  Instantiator {
    model: root.ready && root.hotkeysEnabled ? root.shortcuts : []

    delegate: GlobalShortcut {
      required property var modelData
      appid: root.appId
      name: modelData.name
      description: modelData.description
      onPressed: root.onShortcut(modelData.name)
    }
  }

  property var hyprBinds: []
  // The last `hyprctl binds` worked; until one has, no bind is added or removed.
  property bool bindsKnown: false
  // Hotkeys left out because the user already has their keys bound: [{ name, label, by }].
  property var blockedHotkeys: []
  // Off while the panel records a new hotkey, so our binds don't eat the keys.
  property bool hotkeysPaused: false

  property bool syncing: false
  property bool syncAgain: false

  // Read Hyprland's binds, release what is bound for us, write the file and
  // load it. One at a time, so each read sees the previous result.
  function syncBinds() {
    if (!ready || !hotkeysEnabled) return
    if (syncing) {
      syncAgain = true
      return
    }
    syncing = true
    readBinds(writeBinds)
  }

  function writeBinds() {
    if (!bindsKnown) {
      hotkeysDone()
      return
    }
    var binds = []
    var blocked = []
    shortcuts.forEach(function(sc) {
      var other = Hotkeys.conflict(hyprBinds, sc.keys, Hotkeys.keyNames(keymap, sc.keys, ""), bindPrefix)
      if (other) blocked.push({ name: sc.name, label: sc.label, by: bindLabel(other) })
      else binds.push({ keys: sc.keys, action: sc.name, description: sc.description })
    })
    if (!hotkeysPaused && JSON.stringify(blocked) !== JSON.stringify(blockedHotkeys)) {
      blockedHotkeys = blocked
      if (blocked.length) report(blocked.map(function(b) { return b.label + " is taken by " + b.by }).join("; ")
        + ". Pick other keys in Omarclip's settings.")
    }
    hotkeysTask.start([pluginDir + "/bin/omarclip-hotkeys"], {
      input: JSON.stringify({
        file: bindsPath,
        content: hotkeysPaused ? null : Hotkeys.bindsLua(appId, binds),
        lua: Hotkeys.reloadLua(Hotkeys.ownedKeys(hyprBinds, bindPrefix), hotkeysPaused ? "" : bindsPath)
      })
    })
    log("hotkeys: " + (hotkeysPaused ? "paused while recording a hotkey"
      : binds.length + " bound" + (blocked.length ? ", " + blocked.length + " taken" : "")))
  }

  Task {
    id: hotkeysTask
    onDone: function(exitCode, output, errorOutput) {
      if (exitCode !== 0) root.warn("applying hotkeys failed (" + exitCode + "): " + (output + errorOutput).trim())
      root.hotkeysDone()
    }
  }

  function hotkeysDone() {
    syncing = false
    if (syncAgain) {
      syncAgain = false
      syncBinds()
    }
  }

  function suspendHotkeys() {
    if (!hotkeysEnabled) return readBinds(null)
    if (hotkeysPaused) return
    hotkeysPaused = true
    syncBinds()
  }

  function resumeHotkeys() {
    if (!hotkeysPaused) return
    hotkeysPaused = false
    syncBinds()
  }

  property var bindsReaders: []
  property bool rereadBinds: false

  // keycode -> the key names it produces (Hotkeys.readKeymap), or null when
  // the keymap could not be read. A bind of the user's by key name (ALT, F10)
  // is on the same key as one of ours by keycode (ALT + code:76); this is
  // how the two are matched.
  property var keymap: null

  // Hyprland's binds, then the keyboard's keymap, in one go.
  readonly property var bindsCommand: ["bash", "-c",
    'hyprctl binds || exit 1; printf "\\n%s\\n" "$1"; timeout 5 xkbcli dump-keymap-wayland 2>/dev/null; exit 0',
    "omarclip-binds", "===omarclip-keymap==="]

  function readBinds(then) {
    if (then) bindsReaders = bindsReaders.concat([then])
    if (bindsTask.busy) rereadBinds = true
    else bindsTask.start(bindsCommand)
  }

  Task {
    id: bindsTask
    onDone: function(exitCode, output) {
      root.bindsKnown = exitCode === 0
      var parts = String(output || "").split("\n===omarclip-keymap===\n")
      if (exitCode === 0) {
        root.hyprBinds = Hotkeys.readHyprBinds(parts[0])
        root.keymap = Hotkeys.readKeymap(parts[1] || "")
        if (!root.keymap) root.warn("could not read the keymap; a bind by key name on the same modifiers counts as taken")
      } else {
        // Without them, a bind of ours could land on a key the user has, and
        // unbinding ours would take theirs too.
        root.hyprBinds = []
        root.warn("hyprctl binds failed (" + exitCode + "); hotkeys are left as they are")
      }
      if (root.rereadBinds) {
        root.rereadBinds = false
        bindsTask.start(root.bindsCommand)
        return
      }
      var readers = root.bindsReaders
      root.bindsReaders = []
      readers.forEach(function(then) { then() })
    }
  }

  // What already uses these keys: another Omarclip action or a Hyprland bind.
  function hotkeyConflict(hotkey, action) {
    if (!hotkey) return null
    var used = Config.usedKeys(config)[hotkey.keys]
    if (used && used !== action) return { kind: "omarclip", description: actionLabels[used], action: used }
    var bind = Hotkeys.conflict(hyprBinds, hotkey.keys, Hotkeys.keyNames(keymap, hotkey.keys, hotkey.sym), bindPrefix)
    return bind ? { kind: "hyprland", description: bindLabel(bind) } : null
  }

  // How a bind in the way is named. Without the keymap, a bind by key name
  // may only possibly be on the same key; say so.
  function bindLabel(bind) {
    var name = bind.description || "another bind"
    return keymap || /^code:\d+$/.test(bind.key) ? name : name + " (the keymap could not be read to rule it out)"
  }

  // Keys another action had move here; the panel never offers keys a
  // Hyprland bind already has.
  function assignHotkey(action, hotkey) {
    var value = hotkey ? { keys: hotkey.keys, label: hotkey.label } : null
    var next = config
    var used = value ? Config.usedKeys(next)[value.keys] : ""
    if (used && used !== action) next = Config.withHotkey(next, used, null)
    applyConfig(Config.withHotkey(next, action, value), true)
  }

  property double lastToggle: 0

  function togglePanel() {
    var now = Date.now()
    if (now - lastToggle < 250) return
    lastToggle = now
    if (shell && typeof shell.toggle === "function") shell.toggle(pluginId, "{}")
  }

  function openPanel() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "{}")
  }

  function closePanel() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function statusJson() {
    return JSON.stringify({
      ready: ready,
      enabled: config.enabled,
      status: status,
      detail: statusDetail,
      monitor: recordingMonitor,
      buffered: bufferedSeconds(),
      length: config.length,
      quality: { preset: config.preset, resolution: config.resolution, fps: config.fps, bitrate: config.bitrate, bitrateMbps: Recorder.bitrateFor(config, monitorWidth, monitorHeight), codec: config.codec },
      bufferBytes: bufferBytes,
      storage: config.storage,
      folder: outputDir,
      lastClip: lastClip ? lastClip.path : "",
      hotkeys: shortcuts.map(function(s) { return { action: s.name, keys: s.label } }),
      blocked: blockedHotkeys,
      configBroken: configBroken
    })
  }

  IpcHandler {
    target: root.appId

    // `omarchy-shell omarclip save` keeps the replay length; `save 30` the last 30 s.
    function save(seconds: string): string { return root.saveClip(Number(seconds) || 0) ? "saving" : "not running" }
    function toggle(): void { root.toggleEnabled() }
    function start(): void { root.setEnabled(true) }
    function stop(): void { root.setEnabled(false) }
    function restart(): void { root.syncRecorder(true) }
    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function panel(): void { root.togglePanel() }
    function folder(): void { root.openFolder() }
    function status(): string { return root.statusJson() }
  }
}
