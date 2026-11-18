import { test, after } from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { mkdtempSync, writeFileSync, readFileSync, existsSync, chmodSync, mkdirSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const script = new URL("../bin/omarclip-file", import.meta.url).pathname

const roots = []
after(() => roots.forEach((root) => rmSync(root, { recursive: true, force: true })))

function setup() {
  const root = mkdtempSync(join(tmpdir(), "omarclip-file-"))
  roots.push(root)
  const clip = join(root, "Replay.mp4")
  writeFileSync(clip, "new clip")
  mkdirSync(join(root, "bin"))
  return { root, clip, dir: join(root, "Clips", "Cs2") }
}

// A stand-in for mv, first on PATH.
function fakeMv(root, body) {
  const path = join(root, "bin", "mv")
  writeFileSync(path, "#!/bin/bash\n" + body + "\n")
  chmodSync(path, 0o755)
}

function file({ root, clip, dir }) {
  const out = execFileSync(script, [], {
    input: JSON.stringify({ path: clip, dir, name: "Cs2 2026-11-18 19-30-00", thumbs: "" }),
    env: { ...process.env, PATH: join(root, "bin") + ":" + process.env.PATH },
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"]
  })
  return JSON.parse(out.trim().split("\n").pop())
}

test("files the clip under its name", () => {
  const t = setup()
  const r = file(t)
  assert.equal(r.path, join(t.dir, "Cs2 2026-11-18 19-30-00.mp4"))
  assert.equal(r.filed, true)
  assert.equal(readFileSync(r.path, "utf8"), "new clip")
  assert.ok(!existsSync(t.clip))
})

test("a name already taken gets the next number", () => {
  const t = setup()
  mkdirSync(t.dir, { recursive: true })
  writeFileSync(join(t.dir, "Cs2 2026-11-18 19-30-00.mp4"), "older clip")
  const r = file(t)
  assert.equal(r.path, join(t.dir, "Cs2 2026-11-18 19-30-00 (2).mp4"))
  assert.equal(readFileSync(r.path, "utf8"), "new clip")
  assert.equal(readFileSync(join(t.dir, "Cs2 2026-11-18 19-30-00.mp4"), "utf8"), "older clip")
})

test("a name taken during the move, skipped by mv -n with exit 0, is not reported as the clip", () => {
  const t = setup()
  // Something takes the name just before the move; GNU mv -n then skips it
  // and still exits 0.
  fakeMv(t.root, `dest="\${@: -1}"; [[ $dest == *"19-30-00.mp4" ]] && printf "someone else's" > "$dest"; exec /usr/bin/mv "$@"`)
  const r = file(t)
  assert.equal(r.path, join(t.dir, "Cs2 2026-11-18 19-30-00 (2).mp4"))
  assert.equal(r.filed, true)
  assert.equal(readFileSync(r.path, "utf8"), "new clip")
  assert.equal(readFileSync(join(t.dir, "Cs2 2026-11-18 19-30-00.mp4"), "utf8"), "someone else's")
})

test("a skip that exits 0 every time keeps the clip where it is", () => {
  const t = setup()
  fakeMv(t.root, `dest="\${@: -1}"; echo taken > "$dest"; exit 0`)
  const r = file(t)
  assert.equal(r.path, t.clip)
  assert.equal(r.filed, false)
  assert.equal(readFileSync(t.clip, "utf8"), "new clip")
})

test("a move that fails keeps the clip where it is", () => {
  const t = setup()
  fakeMv(t.root, "exit 1")
  const r = file(t)
  assert.equal(r.path, t.clip)
  assert.equal(r.filed, false)
  assert.equal(readFileSync(t.clip, "utf8"), "new clip")
})
