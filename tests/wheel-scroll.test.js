const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

// ui/WheelScroll.qml under qmltestrunner, offscreen. Skipped where Qt's test
// runner is not installed (CI has no Qt).
const runner = "/usr/lib/qt6/bin/qmltestrunner"

test("wheel and touchpad scrolling follow the system's speed", { skip: !fs.existsSync(runner) && "qmltestrunner not installed" }, () => {
  const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QML_DISABLE_DISK_CACHE: "1" }
  delete env.WAYLAND_DISPLAY
  delete env.DISPLAY
  delete env.QT_QPA_PLATFORMTHEME
  const r = spawnSync(runner, ["-input", path.join(__dirname, "qml/tst_wheelscroll.qml")], { env, encoding: "utf8", timeout: 30000 })
  assert.equal(r.status, 0, r.stdout + r.stderr)
  assert.match(r.stdout, /Totals: \d+ passed, 0 failed/)
})
