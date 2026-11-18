// Hotkeys are stored the way Hyprland takes them, by physical key:
// "ALT + SHIFT + code:76". Qt's nativeScanCode is the XKB keycode on
// Wayland, so a capture works the same on any keyboard layout.

var QT_SHIFT = 0x02000000
var QT_CTRL = 0x04000000
var QT_ALT = 0x08000000
var QT_META = 0x10000000
var QT_KEYPAD = 0x20000000

var MODS = [
  { name: "SUPER", label: "Super", qt: QT_META, mask: 64 },
  { name: "CTRL", label: "Ctrl", qt: QT_CTRL, mask: 4 },
  { name: "ALT", label: "Alt", qt: QT_ALT, mask: 8 },
  { name: "SHIFT", label: "Shift", qt: QT_SHIFT, mask: 1 }
]

var MODIFIER_QT_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000025,
  0x01000053, 0x01000054, 0x01000056, 0x01000057, 0x01001103]

// What a key needs held with it to become a hotkey:
//   solo    nothing: keys nobody types with
//   any     some modifier: keys that edit text or move around
//   strong  Super, Ctrl or Alt: keys that type (Shift alone still types)
var SPECIAL = [
  [0x01000000, "Escape", "Esc", "any"],
  [0x01000001, "Tab", "Tab", "any"],
  [0x01000003, "BackSpace", "Backspace", "any"],
  [0x01000004, "Return", "Enter", "any"],
  [0x01000005, "KP_Enter", "Num Enter", "strong"],
  [0x01000006, "Insert", "Insert", "solo"],
  [0x01000007, "Delete", "Delete", "any"],
  [0x01000008, "Pause", "Pause", "solo"],
  [0x01000009, "Print", "Print", "solo"],
  [0x01000010, "Home", "Home", "solo"],
  [0x01000011, "End", "End", "solo"],
  [0x01000012, "Left", "Left", "any"],
  [0x01000013, "Up", "Up", "any"],
  [0x01000014, "Right", "Right", "any"],
  [0x01000015, "Down", "Down", "any"],
  [0x01000016, "Prior", "PgUp", "solo"],
  [0x01000017, "Next", "PgDn", "solo"],
  [0x01000026, "Scroll_Lock", "ScrollLock", "solo"],
  [0x01000055, "Menu", "Menu", "solo"],
  [0x20, "space", "Space", "strong"]
]

// US-layout names by keycode, for keys Qt reports as a shifted character
// (Shift+1 arrives as "!") and for punctuation.
var KEYCODE_NAMES = (function() {
  var names = {}
  function row(first, chars) { for (var i = 0; i < chars.length; i++) names[first + i] = chars.charAt(i) }
  row(10, "1234567890-=")
  row(24, "QWERTYUIOP[]")
  row(38, "ASDFGHJKL;'`")
  row(51, "\\ZXCVBNM,./")
  for (var f = 1; f <= 10; f++) names[66 + f] = "F" + f
  names[95] = "F11"
  names[96] = "F12"
  var pad = [[79, "7"], [80, "8"], [81, "9"], [82, "-"], [83, "4"], [84, "5"], [85, "6"], [86, "+"],
    [87, "1"], [88, "2"], [89, "3"], [90, "0"], [91, "."], [63, "*"], [106, "/"], [104, "Enter"]]
  for (var p = 0; p < pad.length; p++) names[pad[p][0]] = "Num " + pad[p][1]
  return names
})()

function isModifier(qtKey) {
  return MODIFIER_QT_KEYS.indexOf(Number(qtKey)) !== -1
}

function heldMods(qtModifiers) {
  var bits = Number(qtModifiers) || 0
  return MODS.filter(function(m) { return (bits & m.qt) !== 0 })
}

function describe(qtKey, qtModifiers, keycode) {
  var k = Number(qtKey) || 0
  var keypadName = KEYCODE_NAMES[keycode]
  if ((Number(qtModifiers) & QT_KEYPAD) && keypadName && keypadName.indexOf("Num ") === 0)
    return { sym: "", label: keypadName, rule: "strong" }
  if ((k >= 0x41 && k <= 0x5a) || (k >= 0x30 && k <= 0x39))
    return { sym: String.fromCharCode(k), label: String.fromCharCode(k), rule: "strong" }
  if (k >= 0x01000030 && k <= 0x01000052) {
    var n = k - 0x01000030 + 1
    return { sym: "F" + n, label: "F" + n, rule: "solo" }
  }
  for (var i = 0; i < SPECIAL.length; i++)
    if (SPECIAL[i][0] === k) return { sym: SPECIAL[i][1], label: SPECIAL[i][2], rule: SPECIAL[i][3] }
  var name = KEYCODE_NAMES[keycode]
  if (name) return { sym: "", label: name, rule: /^F\d+$/.test(name) ? "solo" : "strong" }
  return { sym: "", label: "Key " + keycode, rule: "strong" }
}

// One key press while capturing:
//   { phase: "held", labels }          modifiers only, so far
//   { phase: "rejected", why }
//   { phase: "done", keys, label, sym }
function capture(qtKey, qtModifiers, keycode) {
  var mods = heldMods(qtModifiers)
  if (isModifier(qtKey)) return { phase: "held", labels: mods.map(function(m) { return m.label }) }
  var code = Number(keycode) || 0
  if (code < 8 || code > 767) return { phase: "rejected", why: "That key can't be used for a hotkey" }
  var key = describe(qtKey, qtModifiers, code)
  var strong = mods.some(function(m) { return m.name !== "SHIFT" })
  if (key.rule === "strong" && !strong) return { phase: "rejected", why: "Hold Super, Ctrl or Alt with " + key.label + " so it still types" }
  if (key.rule === "any" && mods.length === 0) return { phase: "rejected", why: key.label + " needs a modifier" }
  return {
    phase: "done",
    keys: mods.map(function(m) { return m.name }).concat(["code:" + code]).join(" + "),
    label: mods.map(function(m) { return m.label }).concat([key.label]).join("+"),
    sym: key.sym
  }
}

var KEYS_RE = /^((SUPER|CTRL|ALT|SHIFT) \+ )*code:(\d{1,3})$/

function validKeys(keys) {
  if (typeof keys !== "string") return false
  var m = KEYS_RE.exec(keys)
  if (!m || Number(m[3]) < 8 || Number(m[3]) > 767) return false
  var mods = keys.split(" + ").slice(0, -1)
  return mods.every(function(mod, i) { return mods.indexOf(mod) === i })
}

function maskOf(keys) {
  var parts = String(keys).split(" + ")
  var mask = 0
  MODS.forEach(function(m) { if (parts.indexOf(m.name) !== -1) mask |= m.mask })
  return mask
}

// Lua literal that keeps everything outside a small safe set as a decimal
// byte escape, so no text can close the string or reach the code around it.
function luaQuote(text) {
  var bytes = unescape(encodeURIComponent(String(text === undefined || text === null ? "" : text)))
  var out = "\""
  for (var i = 0; i < bytes.length; i++) {
    var c = bytes.charCodeAt(i)
    out += /[A-Za-z0-9 :+_.,()\/-]/.test(bytes.charAt(i)) ? bytes.charAt(i) : "\\" + c
  }
  return out + "\""
}

var ACTION_RE = /^[a-z][a-z0-9-]{0,31}$/

// The file Omarchy loads on every Hyprland reload. binds: [{ keys, action, description }];
// anything malformed, and a second bind on the same keys, stays out.
function bindsLua(appId, binds) {
  var taken = {}
  var rows = (Array.isArray(binds) ? binds : []).filter(function(b) {
    if (!b || !validKeys(b.keys) || !ACTION_RE.test(String(b.action)) || taken[b.keys]) return false
    taken[b.keys] = true
    return true
  }).map(function(b) {
    return "  { " + [b.keys, b.action, b.description || b.action].map(luaQuote).join(", ") + " },"
  })
  return [
    "-- Omarclip's hotkeys, rewritten whenever they change in its settings.",
    "local app = " + luaQuote(appId),
    "for _, b in ipairs({",
    rows.join("\n"),
    "}) do",
    "  pcall(hl.bind, b[1], hl.dsp.global(app .. \":\" .. b[2]), { description = b[3] })",
    "end",
    ""
  ].filter(function(line, i) { return i !== 3 || line !== "" }).join("\n")
}

// Drops `release` from the running compositor, then loads `file` (if any).
function reloadLua(release, file) {
  var keys = (Array.isArray(release) ? release : []).filter(function(k, i, all) {
    return validKeys(k) && all.indexOf(k) === i
  })
  var lua = []
  if (keys.length) lua.push("for _, k in ipairs({ " + keys.map(luaQuote).join(", ") + " }) do pcall(hl.unbind, k) end")
  if (file) lua.push("dofile(" + luaQuote(file) + ")")
  return lua.join("\n")
}

// `hyprctl binds` in its text form (the JSON leaves keycode binds without a
// key). Each bind: { mask, key, keys, description }, `key` lowercased for
// comparing and `keys` written the way hl.unbind takes it.
function readHyprBinds(text) {
  var binds = []
  var current = null
  String(text || "").split("\n").forEach(function(line) {
    if (/^bind/.test(line)) {
      current = { mask: -1, key: "", keys: "", description: "" }
      binds.push(current)
      return
    }
    var field = /^\s*(modmask|key|description):\s?(.*)$/.exec(line)
    if (!current || !field) return
    if (field[1] === "modmask") current.mask = Number(field[2])
    else if (field[1] === "description") current.description = field[2].trim()
    else current.key = field[2].trim().split(" + ").pop()
  })
  return binds.filter(function(b) { return b.mask >= 0 && b.key }).map(function(b) {
    var names = MODS.filter(function(m) { return (b.mask & m.mask) !== 0 }).map(function(m) { return m.name })
    return {
      mask: b.mask,
      key: /^code:\d+$/.test(b.key) ? b.key : b.key.toLowerCase(),
      keys: names.concat([b.key]).join(" + "),
      description: b.description
    }
  })
}

function mine(bind, prefix) {
  return !!prefix && bind.description.indexOf(prefix) === 0
}

// The first bind that isn't ours on the same keys, matched by keycode or by
// key name (`sym`), or null.
function conflict(binds, keys, sym, ownPrefix) {
  var mask = maskOf(keys)
  var names = [String(keys).split(" + ").pop(), String(sym || "").toLowerCase()]
  return (binds || []).filter(function(b) {
    return !mine(b, ownPrefix) && b.mask === mask && names.indexOf(b.key) !== -1
  })[0] || null
}

// Keys bound for us right now. A key someone else also bound stays: unbinding
// goes by key and would take theirs too.
function ownedKeys(binds, ownPrefix) {
  var list = binds || []
  var shared = {}
  list.forEach(function(b) { if (!mine(b, ownPrefix)) shared[b.mask + " " + b.key] = true })
  var out = []
  list.forEach(function(b) {
    if (mine(b, ownPrefix) && !shared[b.mask + " " + b.key] && out.indexOf(b.keys) === -1) out.push(b.keys)
  })
  return out
}

// ownedKeys as an awk program over `hyprctl binds`, one key per line, for
// the cleanup that runs after the shell has let go of this object (and,
// on removal, after the plugin folder is gone). It reads the binds as they
// are at that moment: a key with no bind of ours, or one the user also
// bound, is left alone. Same rules as ownedKeys; tests keep them in step.
var OWNED_KEYS_AWK = [
  'function flush() { if (inbind && mask >= 0 && key != "") { k = mask " " key; if (prefix != "" && index(desc, prefix) == 1) ours[k] = 1; else other[k] = 1 } }',
  'function bit(m, b) { return int(m / b) % 2 }',
  '/^bind/ { flush(); inbind = 1; mask = -1; key = ""; desc = ""; next }',
  '/^[ \\t]*modmask:/ { sub(/^[ \\t]*modmask:[ \\t]?/, ""); mask = $0 + 0; next }',
  '/^[ \\t]*key:/ { sub(/^[ \\t]*key:[ \\t]?/, ""); gsub(/^[ \\t]+|[ \\t]+$/, ""); n = split($0, parts, / \\+ /); key = parts[n]; if (key !~ /^code:[0-9]+$/) key = tolower(key); next }',
  '/^[ \\t]*description:/ { sub(/^[ \\t]*description:[ \\t]?/, ""); gsub(/^[ \\t]+|[ \\t]+$/, ""); desc = $0; next }',
  'END {',
  '  flush()',
  '  for (k in ours) {',
  '    if (k in other) continue',
  '    split(k, f, " "); m = f[1] + 0; out = ""',
  '    if (bit(m, 64)) out = out "SUPER + "',
  '    if (bit(m, 4)) out = out "CTRL + "',
  '    if (bit(m, 8)) out = out "ALT + "',
  '    if (bit(m, 1)) out = out "SHIFT + "',
  '    print out f[2]',
  '  }',
  '}'
].join("\n")

if (typeof module !== "undefined") {
  module.exports = {
    QT_SHIFT: QT_SHIFT, QT_CTRL: QT_CTRL, QT_ALT: QT_ALT, QT_META: QT_META, QT_KEYPAD: QT_KEYPAD,
    isModifier: isModifier,
    capture: capture,
    validKeys: validKeys,
    luaQuote: luaQuote,
    bindsLua: bindsLua,
    reloadLua: reloadLua,
    readHyprBinds: readHyprBinds,
    conflict: conflict,
    ownedKeys: ownedKeys,
    OWNED_KEYS_AWK: OWNED_KEYS_AWK
  }
}
