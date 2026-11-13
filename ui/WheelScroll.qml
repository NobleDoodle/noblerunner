import QtQuick

// Wheel and touchpad scrolling for a list. Flickable's own wheel handling
// turns each event into a short flick that moves a few pixels.
//
// Touchpad: the list follows the fingers. Hyprland scales touchpad scroll
// by input:touchpad:scroll_factor (Omarchy ships 0.4) and other toolkits
// make up for it with their own scaling and momentum, so the factor is
// divided back out here (touchpadScale) and a flick keeps coasting after
// the fingers lift.
// Mouse wheel: one notch moves the platform's wheelScrollLines rows, as the
// Omarchy menu does.
WheelHandler {
  id: handler

  required property Flickable view
  // One "line" of a wheel notch: the height of a normal row.
  property real lineHeight: 42
  // Multiplies touchpad pixel deltas (speed / Hyprland's touchpad factor).
  property real touchpadScale: 1
  // Multiplies wheel notches.
  property real wheelScale: 1

  // Recent touchpad moves as { t: ms, px: pixels }, for the release velocity.
  property var samples: []
  // Coasting starts when no touchpad event follows within this time, for
  // compositors or Qt versions that never send ScrollEnd.
  property Timer releaseTimer: Timer { interval: 70; onTriggered: handler.release() }

  target: null
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

  function bottom() {
    return handler.view.originY + Math.max(0, handler.view.contentHeight - handler.view.height)
  }

  function scrollBy(pixels) {
    var v = handler.view
    v.contentY = Math.max(v.originY, Math.min(handler.bottom(), v.contentY - pixels))
  }

  // Pixels per second over the last 100 ms of finger movement.
  function velocity(now) {
    var recent = handler.samples.filter(function(s) { return now - s.t <= 100 })
    if (recent.length < 2) return 0
    var sum = 0
    for (var i = 1; i < recent.length; i++) sum += recent[i].px
    var span = (recent[recent.length - 1].t - recent[0].t) / 1000
    return span > 0 ? sum / span : 0
  }

  function release() {
    handler.releaseTimer.stop()
    var v = handler.velocity(Date.now())
    handler.samples = []
    if (Math.abs(v) < 150) return
    // flick() moves the content the way a drag of that speed would.
    handler.view.flick(0, v)
  }

  // delta: a touchpad pixel delta as Qt reports it, before scaling.
  function touchpad(delta, phase) {
    if (handler.view.flicking) handler.view.cancelFlick()
    var pixels = delta * handler.touchpadScale
    if (pixels !== 0) {
      var now = Date.now()
      handler.scrollBy(pixels)
      handler.samples = handler.samples.filter(function(s) { return now - s.t <= 150 }).concat([{ t: now, px: pixels }])
    }
    if (phase === Qt.ScrollEnd) handler.release()
    else handler.releaseTimer.restart()
  }

  onWheel: function(event) {
    if (event.pixelDelta.y !== 0 || (event.angleDelta.y === 0 && event.phase !== Qt.NoScrollPhase)) {
      handler.touchpad(event.pixelDelta.y, event.phase)
    } else {
      handler.scrollBy(event.angleDelta.y / 120 * handler.lineHeight * Qt.styleHints.wheelScrollLines * handler.wheelScale)
    }
    event.accepted = true
  }
}
