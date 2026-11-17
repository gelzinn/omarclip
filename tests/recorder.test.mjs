import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const Config = loadQmlJs("lib/Config.js")
const R = loadQmlJs("lib/Recorder.js")

const ctx = { monitor: "DP-1", socket: "/run/user/1000/omarclip/gsr.sock", output: "/home/u/Videos/Clips", nativeWidth: 2560, nativeHeight: 1440 }

function flag(argv, name) {
  const i = argv.indexOf(name)
  return i === -1 ? undefined : argv[i + 1]
}

test("the default config records a constant-bitrate replay buffer", () => {
  const argv = R.args(Config.normalize({}), ctx)
  assert.equal(flag(argv, "-w"), "DP-1")
  assert.equal(flag(argv, "-r"), "60")
  assert.equal(flag(argv, "-bm"), "cbr")
  // Auto bitrate at 1440p60 in H.264: 0.2 bit per pixel.
  assert.equal(flag(argv, "-q"), "44000")
  assert.equal(flag(argv, "-f"), "60")
  assert.equal(flag(argv, "-k"), "h264")
  assert.equal(flag(argv, "-replay-storage"), "ram")
  assert.equal(flag(argv, "-ipc"), ctx.socket)
  assert.equal(flag(argv, "-o"), ctx.output)
  assert.equal(flag(argv, "-a"), "default_output")
  assert.equal(argv.indexOf("-s"), -1)
})

test("quality settings reach the recorder", () => {
  let c = Config.withSetting(Config.normalize({}), "preset", "low")
  c = Config.withSetting(c, "codec", "av1")
  c = Config.withSetting(c, "length", 300)
  const argv = R.args(c, ctx)
  assert.equal(flag(argv, "-s"), "2560x720")
  assert.equal(flag(argv, "-f"), "30")
  // Auto at 720p30 in AV1 falls below the floor.
  assert.equal(flag(argv, "-q"), "5000")
  assert.equal(flag(argv, "-k"), "av1")
  assert.equal(flag(argv, "-r"), "300")
})

test("never upscales", () => {
  assert.equal(R.scaleArg(1440, 1080), "")
  assert.equal(R.scaleArg(1080, 1080), "")
  assert.equal(R.scaleArg(720, 1080), "2560x720")
  assert.equal(R.scaleArg("native", 1080), "")
  assert.equal(R.scaleArg(720, 0), "2560x720")
})

test("audio: tracks apart or mixed, or none", () => {
  const both = { systemAudio: true, microphone: true, separateTracks: true }
  assert.deepEqual(R.audioArgs(both), ["-a", "default_output", "-a", "default_input"])
  assert.deepEqual(R.audioArgs({ ...both, separateTracks: false }), ["-a", "default_output|default_input"])
  assert.deepEqual(R.audioArgs({ systemAudio: false, microphone: false }), [])
  assert.equal(R.audioTracks(both), 2)
  assert.equal(R.audioTracks({ ...both, separateTracks: false }), 1)
})

test("buffer size follows bitrate and length", () => {
  const c = Config.withSetting(Config.normalize({}), "bitrate", 50)
  // 50 Mbps video + 160 kbps audio for 60 s
  assert.equal(R.bufferBytes(c, 1920, 1080), Math.round((50e6 + 160e3) / 8 * 60))
  assert.equal(R.formatBytes(R.bufferBytes(c, 1920, 1080)), "376 MB")
  assert.equal(R.formatBytes(7.5e9), "7.5 GB")
  assert.equal(R.formatBytes(20e9), "20 GB")
})

test("restart only for settings the recorder uses", () => {
  const c = Config.normalize({})
  assert.equal(R.needsRestart(c, Config.withSetting(c, "bitrate", 60)), true)
  assert.equal(R.needsRestart(c, Config.withSetting(c, "monitor", "HDMI-A-1")), true)
  assert.equal(R.needsRestart(c, Config.withSetting(c, "notify", false)), false)
  assert.equal(R.needsRestart(c, Config.withSetting(c, "organizeByApp", false)), false)
  assert.equal(R.needsRestart(c, Config.withHotkey(c, "save", null)), false)
})

test("clips are filed under a readable app name", () => {
  assert.equal(R.appName("cs2", "Counter-Strike 2"), "Cs2")
  assert.equal(R.appName("steam_app_570", "Dota 2"), "Dota 2")
  assert.equal(R.appName("org.mozilla.firefox", "x"), "Firefox")
  assert.equal(R.appName("", ""), "Desktop")
  assert.equal(R.appName("../../etc", ""), "Etc")
  assert.equal(R.safeName("a/b:c", "x"), "a b c")
  assert.equal(R.safeName("...", "x"), "x")
})

test("quality follows resolution, frame rate and encoder, not just bitrate", () => {
  const base = { resolution: "native", fps: 60, bitrate: 30, codec: "h264" }
  const q = R.quality(base, 1920, 1080)
  assert.equal(q.width, 1920)
  assert.equal(q.height, 1080)
  assert.equal(q.level, "plenty")
  assert.deepEqual(R.outputSize(720, 2560, 1440), { width: 1280, height: 720 })
  assert.deepEqual(R.outputSize(2160, 1920, 1080), { width: 1920, height: 1080 })
  assert.equal(R.quality({ ...base, fps: 144, bitrate: 75 }, 3840, 2160).level, "low")
  assert.equal(R.quality({ ...base, fps: 144, bitrate: 75, codec: "av1" }, 3840, 2160).level, "good")
  assert.equal(R.quality({ ...base, fps: 144, bitrate: 10 }, 2560, 1440).level, "poor")
  assert.equal(R.quality(base, 0, 0).height, 1080)
})

test("auto bitrate, and so the clip size, follows resolution, frame rate and encoder", () => {
  const c = Config.normalize({})
  assert.equal(c.bitrate, "auto")
  assert.equal(R.bitrateFor(c, 1920, 1080), 25)
  assert.equal(R.bitrateFor({ ...c, fps: 144 }, 2560, 1440), 106)
  assert.equal(R.bitrateFor({ ...c, codec: "hevc" }, 1920, 1080), 17)
  assert.equal(R.bitrateFor({ ...c, resolution: 720 }, 1920, 1080), 11)
  assert.equal(R.bitrateFor({ ...c, fps: 144 }, 3840, 2160), 150)
  assert.equal(R.bitrateFor({ ...c, bitrate: 30 }, 3840, 2160), 30)
  assert.ok(R.bufferBytes({ ...c, fps: 30 }, 1920, 1080) < R.bufferBytes(c, 1920, 1080))
})
