import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const Config = loadQmlJs("lib/Config.js")

test("normalize fills defaults for an empty or broken config", () => {
  for (const raw of [undefined, null, "nope", [], {}]) {
    const c = Config.normalize(raw)
    assert.equal(c.version, 1)
    assert.equal(c.enabled, true)
    assert.equal(c.length, 60)
    assert.equal(c.preset, "high")
    assert.equal(c.resolution, "native")
    assert.equal(c.fps, 60)
    assert.equal(c.bitrate, "auto")
    assert.equal(c.codec, "h264")
    assert.equal(c.monitor, "focused")
    assert.equal(c.folder, "~/Videos/Clips")
    assert.equal(c.storage, "ram")
    assert.equal(c.hotkeys.save.keys, "ALT + code:76")
    assert.equal(c.hotkeys.toggle.keys, "ALT + SHIFT + code:76")
    assert.equal(c.hotkeys.open.keys, "ALT + code:52")
  }
})

test("normalize clamps and rejects bad values", () => {
  const c = Config.normalize({ preset: "custom", length: 99999, bitrate: 1, fps: 75, codec: "divx", resolution: 1234,
    monitor: "DP-1; rm -rf ~", folder: "relative/path", storage: "cloud", cursor: "yes" })
  assert.equal(c.length, 1200)
  assert.equal(c.bitrate, 5)
  assert.equal(c.fps, 60)
  assert.equal(c.codec, "h264")
  assert.equal(c.resolution, "native")
  assert.equal(c.monitor, "focused")
  assert.equal(c.folder, "~/Videos/Clips")
  assert.equal(c.storage, "ram")
  assert.equal(c.cursor, true)
  assert.equal(Config.normalize({ length: 3 }).length, 15)
  assert.equal(Config.normalize({ length: true }).length, 60)
})

test("folders: absolute or home-relative, trailing slash dropped", () => {
  assert.equal(Config.normalize({ folder: "/mnt/clips/" }).folder, "/mnt/clips")
  assert.equal(Config.normalize({ folder: "~/Clips" }).folder, "~/Clips")
  assert.equal(Config.normalize({ folder: "/a\nb" }).folder, "~/Videos/Clips")
})

test("picking a preset sets its resolution, frame rate and bitrate", () => {
  const c = Config.withSetting(Config.normalize({}), "preset", "low")
  assert.deepEqual([c.preset, c.resolution, c.fps, c.bitrate], ["low", 720, 30, "auto"])
  const m = Config.withSetting(c, "preset", "medium")
  assert.deepEqual([m.preset, m.resolution, m.fps, m.bitrate], ["medium", 1080, 60, "auto"])
})

test("changing a video value by hand turns the preset into custom", () => {
  const c = Config.withSetting(Config.normalize({}), "bitrate", 80)
  assert.equal(c.preset, "custom")
  assert.equal(c.bitrate, 80)
  assert.equal(c.resolution, "native")
  // Custom keeps its own values when switching back and forth is not involved.
  const d = Config.withSetting(c, "fps", 120)
  assert.deepEqual([d.preset, d.fps, d.bitrate], ["custom", 120, 80])
  // Picking custom itself keeps the values.
  const e = Config.withSetting(Config.normalize({}), "preset", "custom")
  assert.deepEqual([e.preset, e.bitrate], ["custom", "auto"])
  // Going back to auto from a fixed bitrate.
  assert.equal(Config.withSetting(c, "bitrate", "auto").bitrate, "auto")
})

test("a named preset in the file wins over values beside it; no preset means matching one", () => {
  assert.equal(Config.normalize({ preset: "low", bitrate: 90 }).bitrate, "auto")
  assert.equal(Config.normalize({ resolution: 720, fps: 30, bitrate: "auto" }).preset, "low")
  assert.equal(Config.normalize({ resolution: 720, fps: 30, bitrate: 10 }).preset, "custom")
  assert.equal(Config.normalize({ bitrate: 33 }).preset, "custom")
})

test("a cleared hotkey stays cleared; an invalid one is dropped", () => {
  const c = Config.normalize({ hotkeys: { save: null, toggle: { keys: "rm -rf /" } } })
  assert.equal(c.hotkeys.save, null)
  assert.equal(c.hotkeys.toggle, null)
  assert.equal(c.hotkeys.open.label, "Alt+Z")
})

test("usedKeys maps keys to actions", () => {
  const used = Config.usedKeys(Config.normalize({}))
  assert.equal(used["ALT + code:76"], "save")
  assert.equal(used["ALT + SHIFT + code:76"], "toggle")
})

test("updates never mutate their input", () => {
  const c = Config.normalize({})
  const before = JSON.stringify(c)
  Config.withSetting(c, "preset", "low")
  Config.withSetting(c, "bitrate", 90)
  Config.withHotkey(c, "save", null)
  assert.equal(JSON.stringify(c), before)
})

test("replay length steps", () => {
  assert.equal(Config.stepLength(60, 1), 90)
  assert.equal(Config.stepLength(60, -1), 45)
  assert.equal(Config.stepLength(1200, 1), 1200)
  assert.equal(Config.stepLength(15, -1), 15)
  assert.equal(Config.stepLength(100, 1), 120)
  assert.equal(Config.stepLength(100, -1), 90)
})

test("labels", () => {
  assert.equal(Config.formatLength(45), "45 s")
  assert.equal(Config.formatLength(60), "1 min")
  assert.equal(Config.formatLength(90), "1 min 30 s")
  assert.equal(Config.resolutionLabel("native"), "Native")
  assert.equal(Config.resolutionLabel(1080), "1080p")
  assert.equal(Config.presetLabel("custom"), "Custom")
  assert.equal(Config.step(["a", "b", "c"], "c", 1), "a")
  assert.equal(Config.step(["a", "b", "c"], "a", -1), "c")
})
