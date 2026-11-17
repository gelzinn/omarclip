// Turns Omarclip's config into the gpu-screen-recorder replay command, and
// the numbers the settings page shows about it. Pure functions.

var AUDIO_KBPS = 160

// Outputs never upscale: a 1440p setting on a 1080p monitor records 1080p.
// The width allows anything up to 32:9, so an ultrawide keeps its shape and
// only the height decides the size.
function scaleArg(resolution, nativeHeight) {
  if (resolution === "native") return ""
  var h = Number(resolution)
  if (!isFinite(h) || h <= 0) return ""
  if (nativeHeight && h >= nativeHeight) return ""
  return Math.round(h * 32 / 9) + "x" + h
}

function audioArgs(config) {
  var sources = []
  if (config.systemAudio) sources.push("default_output")
  if (config.microphone) sources.push("default_input")
  if (sources.length === 0) return []
  // Several -a flags are several tracks; joined with | they are mixed into one.
  if (config.separateTracks) {
    var out = []
    for (var i = 0; i < sources.length; i++) out.push("-a", sources[i])
    return out
  }
  return ["-a", sources.join("|")]
}

function audioTracks(config) {
  var n = (config.systemAudio ? 1 : 0) + (config.microphone ? 1 : 0)
  if (n > 1 && !config.separateTracks) return 1
  return n
}

var MIN_BITRATE = 5
var MAX_BITRATE = 150
// How much less HEVC and AV1 need for the same picture as H.264.
var CODEC_EFFICIENCY = { h264: 1, hevc: 0.7, av1: 0.6 }
// Auto bitrate: 0.2 bit per pixel in H.264 keeps fast motion sharp
// (1080p60 ≈ 25 Mbps, 1440p144 ≈ 106 Mbps, 720p30 ≈ 6 Mbps).
var AUTO_BITS_PER_PIXEL = 0.2

// The bitrate in Mbps a config records at on a monitor of this size.
function bitrateFor(config, nativeWidth, nativeHeight) {
  if (config.bitrate !== "auto") return Number(config.bitrate)
  var size = outputSize(config.resolution, nativeWidth, nativeHeight)
  var bits = size.width * size.height * config.fps * AUTO_BITS_PER_PIXEL * (CODEC_EFFICIENCY[config.codec] || 1)
  return Math.max(MIN_BITRATE, Math.min(MAX_BITRATE, Math.round(bits / 1e6)))
}

// ctx: { monitor, socket, output, nativeWidth, nativeHeight }
function args(config, ctx) {
  var list = [
    "-w", ctx.monitor,
    "-c", "mp4",
    "-f", String(config.fps),
    "-k", config.codec,
    // Constant bitrate: the buffer's size, and so its memory, stays fixed
    // however busy the picture is. -q is the bitrate in kbps in this mode.
    "-bm", "cbr",
    "-q", String(bitrateFor(config, ctx.nativeWidth, ctx.nativeHeight) * 1000),
    "-r", String(config.length),
    "-replay-storage", config.storage,
    "-restart-replay-on-save", "no",
    // Clips start on a keyframe; one a second keeps them close to the length asked for.
    "-keyint", "1",
    "-cursor", config.cursor ? "yes" : "no",
    "-ac", "aac"
  ]
  var scale = scaleArg(config.resolution, ctx.nativeHeight)
  if (scale) list.push("-s", scale)
  list = list.concat(audioArgs(config))
  list.push("-ipc", ctx.socket, "-o", ctx.output, "-v", "no")
  return list
}

// Bytes the buffer holds once full.
function bufferBytes(config, nativeWidth, nativeHeight) {
  var bitsPerSecond = bitrateFor(config, nativeWidth, nativeHeight) * 1000000 + audioTracks(config) * AUDIO_KBPS * 1000
  return Math.round(bitsPerSecond / 8 * config.length)
}

function formatBytes(bytes) {
  var b = Math.max(0, Number(bytes) || 0)
  if (b >= 1e9) return (b / 1e9).toFixed(b >= 1e10 ? 0 : 1) + " GB"
  if (b >= 1e6) return Math.round(b / 1e6) + " MB"
  return Math.max(1, Math.round(b / 1e3)) + " KB"
}

// The size a clip comes out at: the monitor's own, or scaled down to the
// chosen height keeping its shape. Unknown monitors count as 1920x1080.
function outputSize(resolution, nativeWidth, nativeHeight) {
  var w = Number(nativeWidth) || 1920
  var h = Number(nativeHeight) || 1080
  var want = Number(resolution)
  if (resolution === "native" || !isFinite(want) || want <= 0 || want >= h) return { width: w, height: h }
  return { width: Math.round(want * w / h / 2) * 2, height: want }
}

// How far the bitrate stretches over the pixels it has to cover, as a
// level: "plenty", "good", "low" or "poor".
function quality(config, nativeWidth, nativeHeight) {
  var size = outputSize(config.resolution, nativeWidth, nativeHeight)
  var mbps = bitrateFor(config, nativeWidth, nativeHeight)
  var bitsPerPixel = mbps * 1000000 / (size.width * size.height * config.fps)
  var effective = bitsPerPixel / (CODEC_EFFICIENCY[config.codec] || 1)
  var level = effective >= 0.12 ? "plenty" : effective >= 0.07 ? "good" : effective >= 0.04 ? "low" : "poor"
  return { width: size.width, height: size.height, mbps: mbps, bitsPerPixel: bitsPerPixel, level: level }
}

var QUALITY_TEXT = {
  plenty: "is plenty for that: fast motion stays sharp.",
  good: "looks good for that; very fast motion may soften a little.",
  low: "is on the low side for that: fast motion gets blurry.",
  poor: "is too low for that: fast motion turns blocky. Raise the bitrate or lower the resolution or frame rate."
}

// Settings that need the recorder restarted (which empties the buffer).
var RESTART_KEYS = ["length", "resolution", "fps", "bitrate", "codec", "monitor", "cursor",
  "systemAudio", "microphone", "separateTracks", "folder", "storage"]

function needsRestart(previous, next) {
  for (var i = 0; i < RESTART_KEYS.length; i++) {
    var k = RESTART_KEYS[i]
    if (JSON.stringify(previous[k]) !== JSON.stringify(next[k])) return true
  }
  return false
}

// Folder and file names for a clip: no slashes, controls or leading dots.
function safeName(text, fallback) {
  var s = String(text || "").replace(/[\u0000-\u001f\u007f/\\:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim()
  s = s.replace(/^[.\s]+/, "").slice(0, 64).trim()
  return s || fallback
}

// The app a clip is filed under, from Hyprland's active window.
function appName(windowClass, title) {
  var c = String(windowClass || "")
  // Steam games report steam_app_<id>; the title carries the game's name.
  if (/^steam_app_\d+$/.test(c) && title) return safeName(title, "Game")
  // Reverse-DNS classes (org.mozilla.firefox) read better as their last part.
  if (/^[a-z0-9-]+(\.[A-Za-z0-9-]+){2,}$/.test(c)) c = c.split(".").pop()
  c = safeName(c, "Desktop")
  return c.charAt(0).toUpperCase() + c.slice(1)
}

if (typeof module !== "undefined") {
  module.exports = {
    scaleArg: scaleArg,
    audioArgs: audioArgs,
    audioTracks: audioTracks,
    args: args,
    bufferBytes: bufferBytes,
    formatBytes: formatBytes,
    needsRestart: needsRestart,
    outputSize: outputSize,
    bitrateFor: bitrateFor,
    quality: quality,
    QUALITY_TEXT: QUALITY_TEXT,
    safeName: safeName,
    appName: appName
  }
}
