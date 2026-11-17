import { readFileSync } from "node:fs"
import { compileFunction } from "node:vm"

// lib/*.js are QML JavaScript libraries; they export through `module` when
// one exists.
export function loadQmlJs(path) {
  const source = readFileSync(new URL(`../${path}`, import.meta.url), "utf8").replace(/^\.pragma library$/m, "")
  const module = { exports: {} }
  compileFunction(source, ["module"], { filename: path })(module)
  return module.exports
}
