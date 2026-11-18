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

test("the binds file is written through a temporary file that does not stay", () => {
  const root = sandbox()
  stub(root, "hyprctl", "exit 0")
  const dir = join(root, "toggles", "hypr")
  const file = join(dir, "omarclip.lua")
  const r = spawnSync(bin("omarclip-hotkeys"), [], { input: JSON.stringify({ file, content: "-- binds\n", lua: "" }), env: env(root) })
  assert.equal(r.status, 0, String(r.stderr))
  assert.equal(readFileSync(file, "utf8"), "-- binds\n")
  assert.deepEqual(readdirSync(dir), ["omarclip.lua"])
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
