import QtQuick

// Wheel and touchpad scrolling at the system's own speed. Flickable's
// built-in wheel handling turns each event into a short flick, which on
// Hyprland moves only a few pixels per wheel notch. A touchpad's pixel
// deltas already carry the compositor's scroll_factor and natural-scroll
// setting, so they move the list 1:1. A wheel notch moves the platform's
// wheelScrollLines rows, as the Omarchy menu does.
WheelHandler {
  id: handler

  required property Flickable view
  // One "line" of a wheel notch: the height of a normal row.
  property real lineHeight: 42

  target: null
  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

  function scrollBy(pixels) {
    var v = handler.view
    var top = v.originY
    var bottom = top + Math.max(0, v.contentHeight - v.height)
    v.contentY = Math.max(top, Math.min(bottom, v.contentY - pixels))
  }

  onWheel: function(event) {
    var pixels = event.pixelDelta.y !== 0
      ? event.pixelDelta.y
      : event.angleDelta.y / 120 * handler.lineHeight * Qt.styleHints.wheelScrollLines
    handler.scrollBy(pixels)
    event.accepted = true
  }
}
