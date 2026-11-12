// Slash helpers. /s and every longer prefix of /settings open Settings.
function isSettingsQuery(text) {
  var t = String(text || "").trim().toLowerCase()
  return t.length >= 2 && t.charAt(0) === "/" && "/settings".indexOf(t) === 0
}

if (typeof module !== "undefined") module.exports = { isSettingsQuery: isSettingsQuery }
