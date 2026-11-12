const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

// `noblerunner setup hyprland` against a scratch HOME. A fake hyprctl answers
// `binds -j` from a file and records `reload`, so no real config or compositor
// is touched.
const root = path.join(__dirname, "..")
const cli = path.join(root, "bin/noblerunner")

function scratch(t, binds) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "noblerunner-hotkey-"))
  t.after(() => fs.rmSync(home, { recursive: true, force: true }))
  const hypr = home + "/.config/hypr"
  fs.mkdirSync(hypr, { recursive: true })
  fs.mkdirSync(home + "/bin")
  fs.writeFileSync(hypr + "/hyprland.lua", 'require("hypr.bindings")\n')
  fs.writeFileSync(home + "/binds.json", JSON.stringify(binds || []))
  fs.writeFileSync(home + "/bin/hyprctl",
    '#!/bin/bash\nif [[ $1 == binds ]]; then cat "$HOME/binds.json"; elif [[ $1 == reload ]]; then echo reload >> "$HOME/reloads"; fi\n',
    { mode: 0o755 })
  const run = (...args) => spawnSync(cli, ["setup", "hyprland", ...args], {
    env: { HOME: home, XDG_CONFIG_HOME: home + "/.config", PATH: home + "/bin:" + process.env.PATH },
    encoding: "utf8"
  })
  const read = (name) => fs.readFileSync(hypr + "/" + name, "utf8")
  return { home, hypr, run, read, file: hypr + "/noblerunner.lua" }
}

const dictation = [{ modmask: 8, key: "SPACE", release: false, description: "Toggle dictation" }]
const backups = (s) => fs.readdirSync(s.hypr).filter((f) => f.startsWith("noblerunner.lua.bak-"))

test("each key writes its own bind and requires the file once", (t) => {
  const s = scratch(t)
  const expect = { "alt-space": '"ALT + SPACE"', super: '"SUPER + SUPER_L"', "super-space": '"SUPER + SPACE"' }
  for (const key of Object.keys(expect)) {
    const r = s.run("--key=" + key, "--yes")
    assert.equal(r.status, 0, r.stdout + r.stderr)
    const lua = s.read("noblerunner.lua")
    assert.ok(lua.includes("o.bind(" + expect[key]), key)
    assert.ok(lua.includes("hl.unbind(" + expect[key]), key + " frees its chord first")
    assert.equal(lua.match(/\bo\.bind\(/g).length, 1)
  }
  assert.equal(s.read("hyprland.lua").match(/require\("hypr\.noblerunner"\)/g).length, 1)
  assert.deepEqual(backups(s), [], "files setup wrote are replaced without a backup")
  assert.equal(fs.readFileSync(s.home + "/reloads", "utf8").trim().split("\n").length, 3)
})

test("the Super tap runs the command and fires on release", (t) => {
  const s = scratch(t)
  assert.equal(s.run("--key=super", "--yes").status, 0)
  const lua = s.read("noblerunner.lua")
  assert.match(lua, /\.local\/bin\/noblerunner' toggle/)
  assert.match(lua, /release = true/)
  assert.doesNotMatch(lua.replace(/^--.*$/gm, ""), /hl\.dsp\.global/)
})

test("off removes the file and its require", (t) => {
  const s = scratch(t)
  assert.equal(s.run("--key=alt-space", "--yes").status, 0)
  const r = s.run("--key=off", "--yes")
  assert.equal(r.status, 0, r.stdout + r.stderr)
  assert.ok(!fs.existsSync(s.file))
  assert.doesNotMatch(s.read("hyprland.lua"), /hypr\.noblerunner/)
  assert.match(s.read("hyprland.lua"), /hypr\.bindings/)
})

test("a hand-written file is backed up before it is replaced", (t) => {
  const s = scratch(t)
  const mine = '-- mine\no.bind("SUPER + R", "noblerunner launcher", hl.dsp.global("noblerunner:toggle"))\n'
  fs.writeFileSync(s.file, mine, { mode: 0o600 })
  const r = s.run("--key=super-space", "--yes")
  assert.equal(r.status, 0, r.stdout + r.stderr)
  const kept = backups(s)
  assert.equal(kept.length, 1)
  assert.equal(s.read(kept[0]), mine)
  assert.match(s.read("noblerunner.lua"), /"SUPER \+ SPACE"/)
  assert.equal(fs.statSync(s.file).mode & 0o777, 0o600, "the file keeps its mode")
})

test("without a chosen key, an existing file is kept and a taken Alt+Space is refused", (t) => {
  const kept = scratch(t)
  const mine = 'o.bind("SUPER + R", "noblerunner launcher", hl.dsp.global("noblerunner:toggle"))\n'
  fs.writeFileSync(kept.file, mine)
  assert.equal(kept.run("--yes").status, 0)
  assert.equal(kept.read("noblerunner.lua"), mine)

  const taken = scratch(t, dictation)
  const r = taken.run("--yes")
  assert.notEqual(r.status, 0)
  assert.match(r.stderr, /Toggle dictation/)
  assert.ok(!fs.existsSync(taken.file))
  assert.doesNotMatch(taken.read("hyprland.lua"), /noblerunner/)
})

test("an explicit key takes a chord over and says from what", (t) => {
  const s = scratch(t, dictation)
  const r = s.run("--key=alt-space", "--yes")
  assert.equal(r.status, 0, r.stdout + r.stderr)
  assert.match(r.stdout, /take Alt\+Space from: Toggle dictation/)
  assert.match(s.read("noblerunner.lua"), /"ALT \+ SPACE"/)
})

test("nothing changes without a terminal or --yes, or for an unknown key", (t) => {
  const s = scratch(t)
  for (const args of [["--key=super"], ["--key=meta", "--yes"], ["--bogus"]]) {
    const r = s.run(...args)
    assert.notEqual(r.status, 0, args.join(" "))
    assert.ok(!fs.existsSync(s.file), args.join(" "))
  }
  assert.equal(s.read("hyprland.lua"), 'require("hypr.bindings")\n')
})

test("install.sh rejects an unknown hotkey before doing anything", () => {
  const r = spawnSync(path.join(root, "install.sh"), ["--hotkey=meta"], { encoding: "utf8", env: { PATH: process.env.PATH, HOME: os.tmpdir() } })
  assert.notEqual(r.status, 0)
  assert.match(r.stderr, /alt-space, super, super-space or off/)
})
