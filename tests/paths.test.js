const test = require("node:test")
const assert = require("node:assert/strict")
const Paths = require("../core/Paths.js")

const envOf = (vars) => (name) => vars[name] || ""

test("defaults follow the XDG base directory spec", () => {
  const p = Paths.resolve(envOf({ HOME: "/home/u", XDG_RUNTIME_DIR: "/run/user/1000" }))
  assert.equal(p.config, "/home/u/.config/noblerunner")
  assert.equal(p.configFile, "/home/u/.config/noblerunner/config.json")
  assert.equal(p.db, "/home/u/.local/share/noblerunner/db")
  assert.equal(p.extensions, "/home/u/.local/share/noblerunner/extensions")
  assert.equal(p.cache, "/home/u/.cache/noblerunner")
  assert.equal(p.logs, "/home/u/.local/state/noblerunner/logs")
  assert.equal(p.runtime, "/run/user/1000/noblerunner")
  assert.equal(p.scriptCommands, "/home/u/.config/noblerunner/script-commands")
})

test("absolute XDG overrides win, relative ones are ignored", () => {
  const p = Paths.resolve(envOf({
    HOME: "/home/u/",
    XDG_CONFIG_HOME: "/cfg/",
    XDG_DATA_HOME: "relative/data",
    XDG_STATE_HOME: "/st"
  }))
  assert.equal(p.config, "/cfg/noblerunner")
  assert.equal(p.data, "/home/u/.local/share/noblerunner")
  assert.equal(p.state, "/st/noblerunner")
})

test("missing HOME is an error", () => {
  assert.throws(() => Paths.resolve(envOf({})), /HOME is not set/)
})

test("startup creates the persistent dirs and the runtime dir", () => {
  const p = Paths.resolve(envOf({ HOME: "/h", XDG_RUNTIME_DIR: "/r" }))
  assert.deepEqual(Paths.directoriesToCreate(p), [
    "/h/.config/noblerunner", "/h/.local/share/noblerunner/db", "/h/.cache/noblerunner",
    "/h/.local/state/noblerunner/logs", "/h/.local/state/noblerunner/backups", "/r/noblerunner"
  ])
})

test("directories under the old omacast name move to noblerunner", () => {
  const p = Paths.resolve(envOf({ HOME: "/h", XDG_CONFIG_HOME: "/cfg" }))
  assert.deepEqual(Paths.legacyMoves(p), [
    ["/cfg/omacast", "/cfg/noblerunner"],
    ["/h/.local/share/omacast", "/h/.local/share/noblerunner"],
    ["/h/.cache/omacast", "/h/.cache/noblerunner"],
    ["/h/.local/state/omacast", "/h/.local/state/noblerunner"]
  ])
})
