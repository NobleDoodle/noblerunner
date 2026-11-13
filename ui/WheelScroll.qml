import QtQuick

// Wheel and touchpad scrolling for a list. Flickable's own wheel handling
// turns each event into a short flick that moves a few pixels.
//
// Touchpad: Qt on Wayland rounds a touchpad step to whole pixels in
// pixelDelta (mostly 0, -1 or -2) and keeps the exact amount in angleDelta,
// at 12 units per pixel, so the exact value is used. Hyprland has already
// scaled it by input:touchpad:scroll_factor (Omarchy ships 0.4), which other
// toolkits make up for with their own gain and momentum; touchpadScale does
// that here, and a quick swipe keeps coasting after the fingers lift.
// The coast is run here, frame by frame, not with Flickable.flick(): the
// list stops its own motion when the lift (ScrollEnd) reaches it, which
// killed a flick started for that same lift.
// Mouse wheel: one notch moves the platform's wheelScrollLines rows, as the
// Omarchy menu does.
WheelHandler {
  id: handler

  required property Flickable view
  // One "line" of a wheel notch: the height of a normal row.
  property real lineHeight: 42
  // Multiplies exact touchpad pixels.
  property real touchpadScale: 1
  // Multiplies wheel notches.
  property real wheelScale: 1
  // How far a flick coasts. 1 is the default; 2 coasts twice as far.
  property real coast: 1
  // Coasting speed in pixels per second; it decays like a browser fling,
  // losing about 95% of its speed per second at coast 1.
  property real coastVelocity: 0
  readonly property bool coasting: coaster.running
  // The contentY this handler last set, to notice when something else
  // (the keyboard, a new search) moves the list and stop coasting.
  property real coastY: 0
  property FrameAnimation coaster: FrameAnimation {
    onTriggered: handler.coastStep(frameTime)
  }

  // Recent touchpad moves as { t: ms, px: pixels }, for the release velocity.
  property var samples: []
  // Once a ScrollEnd has arrived, the fingers' lift is always reported and
  // the timer below is never needed. Without that, a finger resting on the
  // pad mid-swipe would start a coast.
  property bool endsReported: false
  // For compositors or Qt versions that never send ScrollEnd: coasting
  // starts when no touchpad event follows within this time.
  property Timer releaseTimer: Timer { interval: 70; onTriggered: handler.release() }

  // After each lift: the measured speed and whether the list coasted.
  signal released(real velocity, bool coasted)

  target: null
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

  function bottom() {
    return handler.view.originY + Math.max(0, handler.view.contentHeight - handler.view.height)
  }

  function scrollBy(pixels) {
    var v = handler.view
    v.contentY = Math.max(v.originY, Math.min(handler.bottom(), v.contentY - pixels))
  }

  // Pixels per second over the last 80 ms of finger movement, measured back
  // from the last move, not from the lift: the lift can arrive a while later.
  // Fingers that rested (no move in the 100 ms before the lift) give 0.
  function velocity(now) {
    var n = handler.samples.length
    if (n < 2) return 0
    var last = handler.samples[n - 1].t
    if (now - last > 100) return 0
    var recent = handler.samples.filter(function(s) { return last - s.t <= 80 })
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
    if (Math.abs(v) < 300) { handler.released(v, false); return }
    handler.coastVelocity = v
    handler.coastY = handler.view.contentY
    handler.coaster.start()
    handler.released(v, true)
  }

  function stopCoasting() {
    handler.coaster.stop()
    handler.coastVelocity = 0
  }

  // seconds: time since the last frame.
  function coastStep(seconds) {
    var v = handler.view
    if (Math.abs(v.contentY - handler.coastY) > 0.5) { handler.stopCoasting(); return }
    var dt = Math.min(0.05, Math.max(0, seconds))
    // Time constant 0.33 s at coast 1: the distance is about speed * 0.33 s.
    handler.coastVelocity *= Math.exp(-dt / (0.33 * Math.max(0.1, handler.coast)))
    var before = v.contentY
    handler.scrollBy(handler.coastVelocity * dt)
    handler.coastY = v.contentY
    if (Math.abs(handler.coastVelocity) < 20 || v.contentY === before && dt > 0) handler.stopCoasting()
  }

  // delta: exact touchpad pixels, before scaling.
  function touchpad(delta, phase) {
    handler.stopCoasting()
    var pixels = delta * handler.touchpadScale
    if (pixels !== 0) {
      var now = Date.now()
      handler.scrollBy(pixels)
      handler.samples = handler.samples.filter(function(s) { return now - s.t <= 150 }).concat([{ t: now, px: pixels }])
    }
    if (phase === Qt.ScrollEnd) {
      handler.endsReported = true
      handler.release()
    } else if (!handler.endsReported) {
      handler.releaseTimer.restart()
    }
  }

  function isTouchpad(event) {
    return event.phase !== Qt.NoScrollPhase
      || (event.device && event.device.type === PointerDevice.TouchPad)
  }

  onWheel: function(event) {
    if (handler.isTouchpad(event)) {
      var exact = event.angleDelta.y !== 0 ? event.angleDelta.y / 12 : event.pixelDelta.y
      handler.touchpad(exact, event.phase)
    } else {
      handler.stopCoasting()
      handler.scrollBy(event.angleDelta.y / 120 * handler.lineHeight * Qt.styleHints.wheelScrollLines * handler.wheelScale)
    }
    event.accepted = true
  }
}
