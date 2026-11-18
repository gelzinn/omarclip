// Omarclip's settings file (~/.config/omarclip/config.json): defaults,
// validation and the quality presets. Pure functions; every update returns a
// new object so QML bindings see the change.

var VERSION = 1
var DEFAULT_FOLDER = "~/Videos/Clips"

// Instant replay length, in seconds: what one press of the save hotkey keeps,
// counted back from the press. 15 s to 20 min, like ShadowPlay.
var LENGTHS = [15, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200]
var MIN_LENGTH = 15
var MAX_LENGTH = 1200

// "native" keeps the monitor's resolution; the rest are output heights.
var RESOLUTIONS = ["native", 2160, 1440, 1080, 900, 720, 480, 360]
var FRAMERATES = [30, 60, 120, 144]
var CODECS = ["h264", "hevc", "av1"]
var CODEC_LABEL = { h264: "H.264", hevc: "HEVC (H.265)", av1: "AV1" }
var MIN_BITRATE = 5
var MAX_BITRATE = 150

// Each preset is a resolution and frame rate. Bitrate "auto" follows them
// and the encoder (see Recorder.bitrateFor), so a clip's size does too.
// Changing a value by hand turns the preset into "custom".
var PRESETS = {
  low: { label: "Low", resolution: 720, fps: 30, bitrate: "auto" },
  medium: { label: "Medium", resolution: 1080, fps: 60, bitrate: "auto" },
  high: { label: "High", resolution: "native", fps: 60, bitrate: "auto" }
}
var PRESET_ORDER = ["low", "medium", "high", "custom"]
var VIDEO_KEYS = ["resolution", "fps", "bitrate"]

// Hotkeys come from a capture, always by keycode; anything else in a
// hand-edited config is dropped before it can reach Hyprland.
function validKeys(keys) {
  if (typeof keys !== "string") return false
  var m = /^((SUPER|CTRL|ALT|SHIFT) \+ )*code:(\d{1,3})$/.exec(keys)
  if (!m || Number(m[3]) < 8 || Number(m[3]) > 767) return false
  var mods = keys.split(" + ").slice(0, -1)
  return mods.every(function(mod, i) { return mods.indexOf(mod) === i })
}

function defaults() {
  return {
    version: VERSION,
    // Keep the replay buffer running. The toggle hotkey flips this.
    enabled: true,
    length: 60,
    preset: "high",
    resolution: PRESETS.high.resolution,
    fps: PRESETS.high.fps,
    bitrate: PRESETS.high.bitrate,
    codec: "h264",
    // "focused": the monitor in focus when the buffer starts; or a name like DP-1.
    monitor: "focused",
    cursor: true,
    systemAudio: true,
    microphone: false,
    // Mic on its own audio track instead of mixed into the system audio.
    separateTracks: true,
    folder: DEFAULT_FOLDER,
    // Clips/<App>/<App> 2026-11-16 21-04-11.mp4, like ShadowPlay's game folders.
    organizeByApp: true,
    // Where the buffer lives: "ram" (default) or "disk" for very long replays.
    storage: "ram",
    notify: true,
    hotkeys: {
      save: { keys: "ALT + code:76", label: "Alt+F10" },
      toggle: { keys: "ALT + SHIFT + code:76", label: "Alt+Shift+F10" },
      open: { keys: "ALT + code:52", label: "Alt+Z" }
    }
  }
}

// What runs while an existing config.json cannot be read or parsed: the
// user's choices are unknown, so nothing is captured until they are known
// again (the file is fixed) or the user turns recording on themselves.
function fallback() {
  var c = defaults()
  c.enabled = false
  c.systemAudio = false
  c.microphone = false
  return c
}

var HOTKEY_NAMES = ["save", "toggle", "open"]

function clone(value) {
  return JSON.parse(JSON.stringify(value === undefined ? null : value))
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function clamp(value, min, max, fallback) {
  var n = Number(value)
  if (value === null || value === undefined || value === "" || typeof value === "boolean" || !isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.round(n)))
}

function bool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

// For the switches that start capture: a value that is there but not a
// boolean ("false", 0) is an unclear choice, and an unclear choice records
// nothing. Only a missing key takes the default.
function captureBool(value, fallback) {
  if (value === undefined) return fallback
  return typeof value === "boolean" ? value : false
}

function oneOf(value, list, fallback) {
  return list.indexOf(value) !== -1 ? value : fallback
}

function hotkey(value) {
  if (!isObject(value) || !validKeys(value.keys)) return null
  var label = typeof value.label === "string" && value.label.trim() ? value.label.trim().slice(0, 48) : value.keys
  return { keys: value.keys, label: label }
}

function resolution(value, fallback) {
  if (value === "native") return "native"
  var n = Number(value)
  return RESOLUTIONS.indexOf(n) !== -1 ? n : fallback
}

// Monitor names as Hyprland and gpu-screen-recorder print them (DP-1, HDMI-A-1, eDP-1).
function monitor(value) {
  if (typeof value !== "string") return "focused"
  var v = value.trim()
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(v) ? v : "focused"
}

function folder(value) {
  var v = typeof value === "string" ? value.trim() : ""
  if (!v || v.length > 512 || /[\u0000-\u001f]/.test(v)) return DEFAULT_FOLDER
  if (v.charAt(0) !== "/" && v.indexOf("~/") !== 0 && v !== "~") return DEFAULT_FOLDER
  return v.replace(/\/+$/, "") || "/"
}

// The preset whose values these are, or "custom".
function matchPreset(cfg) {
  for (var name in PRESETS) {
    var p = PRESETS[name]
    if (p.resolution === cfg.resolution && p.fps === cfg.fps && p.bitrate === cfg.bitrate) return name
  }
  return "custom"
}

// Fills gaps with defaults and drops anything malformed. Returns a fresh
// object; the input is never modified.
function normalize(raw) {
  var base = defaults()
  var src = isObject(raw) ? raw : {}
  var out = {
    version: VERSION,
    enabled: captureBool(src.enabled, base.enabled),
    length: clamp(src.length, MIN_LENGTH, MAX_LENGTH, base.length),
    preset: oneOf(src.preset, PRESET_ORDER, base.preset),
    resolution: resolution(src.resolution, base.resolution),
    fps: oneOf(Number(src.fps), FRAMERATES, base.fps),
    bitrate: src.bitrate === "auto" ? "auto" : clamp(src.bitrate, MIN_BITRATE, MAX_BITRATE, base.bitrate),
    codec: oneOf(src.codec, CODECS, base.codec),
    monitor: monitor(src.monitor),
    cursor: bool(src.cursor, base.cursor),
    systemAudio: captureBool(src.systemAudio, base.systemAudio),
    microphone: captureBool(src.microphone, base.microphone),
    separateTracks: bool(src.separateTracks, base.separateTracks),
    folder: folder(src.folder),
    organizeByApp: bool(src.organizeByApp, base.organizeByApp),
    storage: oneOf(src.storage, ["ram", "disk"], base.storage),
    notify: bool(src.notify, base.notify),
    hotkeys: {}
  }
  // A named preset decides the video values; a file edited by hand that
  // names one and also sets other values follows the preset.
  if (out.preset !== "custom") {
    var p = PRESETS[out.preset]
    var hand = src.preset === undefined
    if (hand) out.preset = matchPreset(out)
    else {
      out.resolution = p.resolution
      out.fps = p.fps
      out.bitrate = p.bitrate
    }
  }
  var hotkeys = isObject(src.hotkeys) ? src.hotkeys : {}
  for (var i = 0; i < HOTKEY_NAMES.length; i++) {
    var name = HOTKEY_NAMES[i]
    // An explicit null means the user cleared it; missing means default.
    out.hotkeys[name] = hotkeys[name] === undefined ? base.hotkeys[name] : hotkey(hotkeys[name])
  }
  return out
}

function withSetting(config, key, value) {
  var next = clone(config)
  next[key] = value
  if (key === "preset" && PRESETS[value]) {
    next.resolution = PRESETS[value].resolution
    next.fps = PRESETS[value].fps
    next.bitrate = PRESETS[value].bitrate
  } else if (VIDEO_KEYS.indexOf(key) !== -1) {
    next.preset = "custom"
  }
  return normalize(next)
}

function withHotkey(config, name, value) {
  var next = clone(config)
  if (!isObject(next.hotkeys)) next.hotkeys = {}
  next.hotkeys[name] = value
  return normalize(next)
}

// Keys used anywhere in the config, with the action that uses them.
function usedKeys(config) {
  var out = {}
  var c = normalize(config)
  for (var name in c.hotkeys) if (c.hotkeys[name]) out[c.hotkeys[name].keys] = name
  return out
}

// One step along a list of choices, wrapping around.
function step(list, current, delta) {
  var at = list.indexOf(current)
  if (at === -1) at = 0
  return list[(at + delta + list.length) % list.length]
}

// The next replay length up or down, landing on the steps but keeping a
// length edited by hand reachable.
function stepLength(current, delta) {
  if (delta > 0) {
    for (var i = 0; i < LENGTHS.length; i++) if (LENGTHS[i] > current) return LENGTHS[i]
    return MAX_LENGTH
  }
  for (var j = LENGTHS.length - 1; j >= 0; j--) if (LENGTHS[j] < current) return LENGTHS[j]
  return MIN_LENGTH
}

function formatLength(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  if (s < 60) return s + " s"
  var m = Math.floor(s / 60)
  var rest = s % 60
  return rest ? m + " min " + rest + " s" : m + " min"
}

function resolutionLabel(value) {
  return value === "native" ? "Native" : value + "p"
}

function presetLabel(name) {
  return PRESETS[name] ? PRESETS[name].label : "Custom"
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION,
    DEFAULT_FOLDER: DEFAULT_FOLDER,
    LENGTHS: LENGTHS,
    RESOLUTIONS: RESOLUTIONS,
    FRAMERATES: FRAMERATES,
    CODECS: CODECS,
    CODEC_LABEL: CODEC_LABEL,
    PRESETS: PRESETS,
    PRESET_ORDER: PRESET_ORDER,
    MIN_BITRATE: MIN_BITRATE,
    MAX_BITRATE: MAX_BITRATE,
    defaults: defaults,
    fallback: fallback,
    normalize: normalize,
    validKeys: validKeys,
    withSetting: withSetting,
    withHotkey: withHotkey,
    usedKeys: usedKeys,
    matchPreset: matchPreset,
    step: step,
    stepLength: stepLength,
    formatLength: formatLength,
    resolutionLabel: resolutionLabel,
    presetLabel: presetLabel
  }
}
