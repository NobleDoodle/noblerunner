.pragma library

// Type only. Layout sizes stay on uiZoom; this is 20% smaller than those.
var scale = 0.8

function px(size) {
  return Math.max(1, Math.round(Number(size) * scale))
}
