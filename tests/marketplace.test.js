const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

// The repo root is what `omarchy plugin add` installs. These mirror
// omarchy-plugin-validate and the marketplace's SUBMISSION.md, so CI catches
// a broken listing without Omarchy installed.
const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

test("manifest has every field the marketplace lists", () => {
  assert.equal(manifest.schemaVersion, 1)
  for (const field of ["id", "name", "version", "author", "description", "kinds", "entryPoints"]) {
    assert.ok(manifest[field], `missing ${field}`)
  }
  assert.equal(manifest.id, "nobledoodle.noblerunner")
  assert.equal(manifest.name, "noblerunner")
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.ok(!manifest.id.startsWith("omarchy."))
  assert.ok(manifest.version.length <= 64)
})

test("every kind has an entry point that exists", () => {
  for (const kind of manifest.kinds) {
    const entry = manifest.entryPoints[kind]
    assert.ok(entry, `kind ${kind} has no entry point`)
    assert.ok(!path.isAbsolute(entry) && !entry.includes(".."))
    assert.ok(fs.statSync(path.join(root, entry)).isFile(), `${entry} not found`)
  }
})

test("root has a README and a license", () => {
  assert.ok(fs.existsSync(path.join(root, "README.md")))
  assert.match(fs.readFileSync(path.join(root, "LICENSE"), "utf8"), /^MIT License/)
  assert.ok(fs.statSync(path.join(root, "preview.png")).size > 1000)
})

test("install.sh checks the runtime dependencies after plugin add", () => {
  const script = fs.readFileSync(path.join(root, "install.sh"), "utf8")
  for (const cmd of ["omarchy-shell", "socat", "jq", "hyprctl"]) assert.match(script, new RegExp(cmd))
  assert.match(script, /omarchy plugin add/)
  assert.match(script, /--hotkey/)
})

const inGit = fs.existsSync(path.join(root, ".git"))

test("no tracked symlinks, which the shell refuses inside a plugin", { skip: !inGit && "not a git checkout" }, () => {
  const files = execFileSync("git", ["ls-files", "-s"], { cwd: root, encoding: "utf8" })
  const links = files.split("\n").filter((line) => line.startsWith("120000"))
  assert.deepEqual(links, [])
})
