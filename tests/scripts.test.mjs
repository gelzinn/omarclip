import { test, after } from "node:test"
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, existsSync, chmodSync, mkdirSync, symlinkSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const bin = (name) => new URL(`../bin/${name}`, import.meta.url).pathname
const roots = []
after(() => roots.forEach((root) => rmSync(root, { recursive: true, force: true })))

function sandbox() {
  const root = mkdtempSync(join(tmpdir(), "omarclip-scripts-"))
  roots.push(root)
  mkdirSync(join(root, "bin"))
  return root
}

function stub(root, name, body) {
  const path = join(root, "bin", name)
  writeFileSync(path, "#!/bin/bash\n" + body + "\n")
  chmodSync(path, 0o755)
}

const env = (root) => ({ ...process.env, PATH: join(root, "bin") + ":" + process.env.PATH })

test("the hotkeys helper removes an old binds file and saves none", () => {
  const root = sandbox()
  const evals = join(root, "evals")
  stub(root, "hyprctl", `printf '%s\\n' "$*" >> ${JSON.stringify(evals)}`)
  const dir = join(root, "toggles", "hypr")
  mkdirSync(dir, { recursive: true })
  const stale = join(dir, "omarclip.lua")
  writeFileSync(stale, "-- old binds\n")
  writeFileSync(join(dir, "flags.lua"), "-- not ours\n")
  const r = spawnSync(bin("omarclip-hotkeys"), [], { input: JSON.stringify({ stale, lua: "pcall(hl.bind)" }), env: env(root) })
  assert.equal(r.status, 0, String(r.stderr))
  assert.deepEqual(readdirSync(dir), ["flags.lua"])
  assert.equal(readFileSync(evals, "utf8"), "eval pcall(hl.bind)\n")
})

test("the hotkeys helper removes nothing outside a toggles folder", () => {
  const root = sandbox()
  stub(root, "hyprctl", "exit 0")
  const other = join(root, "other.lua")
  writeFileSync(other, "-- keep\n")
  const r = spawnSync(bin("omarclip-hotkeys"), [], { input: JSON.stringify({ stale: other, lua: "" }), env: env(root) })
  assert.equal(r.status, 2)
  assert.ok(existsSync(other))
})

test("the recorder refuses a runtime folder that is a symlink", () => {
  const root = sandbox()
  const marker = join(root, "recorded")
  stub(root, "gpu-screen-recorder", `touch ${JSON.stringify(marker)}`)
  const elsewhere = join(root, "elsewhere")
  mkdirSync(elsewhere, { mode: 0o755 })
  const runtime = join(root, "runtime")
  symlinkSync(elsewhere, runtime)
  const r = spawnSync(bin("omarclip-recorder"), [runtime, join(root, "cache"), join(root, "out"), "--"], { env: env(root) })
  assert.equal(r.status, 1)
  assert.match(String(r.stderr), /is not a folder of yours/)
  assert.ok(!existsSync(marker))
  assert.ok(!existsSync(join(elsewhere, "recorder.pid")))
})

test("the recorder runs from a runtime folder of its own", () => {
  const root = sandbox()
  const marker = join(root, "recorded")
  stub(root, "gpu-screen-recorder", `touch ${JSON.stringify(marker)}`)
  const runtime = join(root, "runtime")
  const r = spawnSync(bin("omarclip-recorder"), [runtime, join(root, "cache"), join(root, "out"), "--"], { env: env(root) })
  assert.equal(r.status, 0, String(r.stderr))
  assert.ok(existsSync(marker))
  assert.ok(existsSync(join(runtime, "recorder.pid")))
})
