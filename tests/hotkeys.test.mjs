import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const H = loadQmlJs("lib/Hotkeys.js")
const Config = loadQmlJs("lib/Config.js")

const Q = { F10: 0x01000039, PgUp: 0x01000016, Up: 0x01000013, Enter: 0x01000004, Shift: 0x01000020, Z: 0x5a, Exclam: 0x21 }

test("modifiers alone keep the capture going", () => {
  const r = H.capture(Q.Shift, H.QT_SHIFT | H.QT_ALT, 50)
  assert.equal(r.phase, "held")
  assert.deepEqual([...r.labels], ["Alt", "Shift"])
})

test("F-keys, PgUp and the like work alone", () => {
  assert.deepEqual({ ...H.capture(Q.F10, 0, 76) }, { phase: "done", keys: "code:76", label: "F10", sym: "F10" })
  assert.equal(H.capture(Q.PgUp, 0, 112).label, "PgUp")
  assert.equal(H.capture(Q.F10, H.QT_ALT, 76).keys, "ALT + code:76")
})

test("typing keys need Super, Ctrl or Alt; Shift alone is not enough", () => {
  assert.equal(H.capture(Q.Z, 0, 52).phase, "rejected")
  assert.equal(H.capture(Q.Z, H.QT_SHIFT, 52).phase, "rejected")
  const r = H.capture(Q.Z, H.QT_META | H.QT_SHIFT, 52)
  assert.equal(r.keys, "SUPER + SHIFT + code:52")
  assert.equal(r.label, "Super+Shift+Z")
})

test("arrows and Enter need some modifier", () => {
  assert.equal(H.capture(Q.Up, 0, 111).phase, "rejected")
  assert.equal(H.capture(Q.Enter, 0, 36).phase, "rejected")
  assert.equal(H.capture(Q.Up, H.QT_SHIFT, 111).phase, "done")
})

test("a shifted character is named after its key", () => {
  assert.equal(H.capture(Q.Exclam, H.QT_CTRL | H.QT_SHIFT, 10).label, "Ctrl+Shift+1")
  assert.equal(H.capture(0x31, H.QT_KEYPAD | H.QT_CTRL, 87).label, "Ctrl+Num 1")
})

test("only keycode hotkeys with known, unrepeated modifiers are valid", () => {
  for (const ok of ["code:76", "ALT + code:76", "SUPER + CTRL + ALT + SHIFT + code:112"]) {
    assert.ok(H.validKeys(ok), ok)
    assert.ok(Config.validKeys(ok), ok)
  }
  for (const bad of ["ALT + ALT + code:76", "HYPER + code:76", "ALT + Z", "code:5", "code:999", "ALT + code:76\")", 7]) {
    assert.ok(!H.validKeys(bad), String(bad))
    assert.ok(!Config.validKeys(bad), String(bad))
  }
})

test("Lua strings can't be broken out of", () => {
  assert.equal(H.luaQuote("Omarclip: save clip"), "\"Omarclip: save clip\"")
  assert.equal(H.luaQuote("a\"b\\c\nd"), "\"a\\34b\\92c\\10d\"")
  assert.equal(H.luaQuote("é"), "\"\\195\\169\"")
})

test("the binds file keeps valid, distinct binds only", () => {
  const lua = H.bindsLua("omarclip", [
    { keys: "ALT + code:76", action: "save", description: "Omarclip: save clip" },
    { keys: "ALT + code:76", action: "toggle", description: "same keys" },
    { keys: "code:112\") os.exit(\"", action: "open", description: "x" },
    { keys: "code:117", action: "../x", description: "x" }
  ])
  assert.match(lua, /\{ "ALT \+ code:76", "save", "Omarclip: save clip" \},/)
  assert.ok(!lua.includes("toggle"))
  assert.ok(!lua.includes("os.exit"))
  assert.ok(!lua.includes("../x"))
  assert.match(lua, /hl\.dsp\.global\(app \.\. ":" \.\. b\[2\]\)/)
})

test("reloading releases old keys once, then loads the file", () => {
  const lua = H.reloadLua(["code:112", "code:112", "bogus"], "/s/omarclip.lua")
  assert.equal(lua, "for _, k in ipairs({ \"code:112\" }) do pcall(hl.unbind, k) end\ndofile(\"/s/omarclip.lua\")")
  assert.equal(H.reloadLua([], ""), "")
})

const BINDS = `bindd
	modmask: 68
	submap:
	key: Z
	keycode: 0
	description: Zoom in
	dispatcher: __lua

bindd
	modmask: 0
	key: code:112
	description: Omarclip: save clip

bindd
	modmask: 8
	key: ALT + code:52
	description: Omarclip: open omarclip

bindd
	modmask: 8
	key: code:52
	description: Something of the user's
`

test("reads hyprctl binds and tells ours from the user's", () => {
  const binds = H.readHyprBinds(BINDS)
  assert.equal(binds.length, 4)
  assert.deepEqual({ ...binds[0] }, { mask: 68, key: "z", keys: "SUPER + CTRL + Z", description: "Zoom in" })
  assert.equal(binds[2].keys, "ALT + code:52")
  assert.deepEqual([...H.ownedKeys(binds, "Omarclip: ")], ["code:112"])
})

test("conflicts come from other binds, by keycode or key name", () => {
  const binds = H.readHyprBinds(BINDS)
  assert.equal(H.conflict(binds, "SUPER + CTRL + code:52", "Z", "Omarclip: ").description, "Zoom in")
  assert.equal(H.conflict(binds, "code:112", "Prior", "Omarclip: "), null)
  assert.equal(H.conflict(binds, "ALT + code:52", "Z", "Omarclip: ").description, "Something of the user's")
})
