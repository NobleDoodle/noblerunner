import QtQuick
import QtTest
import "../../ui"

// Real wheel events, sent the way QtTest sends them, against a 40-row list.
Item {
  width: 300; height: 200

  ListView {
    id: list
    anchors.fill: parent
    model: 40
    boundsBehavior: Flickable.StopAtBounds
    // Like ResultRow: each row has a hover and click MouseArea on top.
    delegate: Rectangle {
      width: 300; height: 20
      MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: {} }
    }
    WheelScroll { id: handler; view: list; lineHeight: 20 }
  }

  TestCase {
    name: "WheelScroll"
    when: windowShown

    function init() { list.cancelFlick(); handler.samples = []; list.contentY = list.originY }

    function test_wheelNotchMovesLines() {
      mouseWheel(list, 150, 100, 0, -120)
      compare(list.contentY - list.originY, 20 * Qt.styleHints.wheelScrollLines)
    }

    // QtTest cannot send pixel deltas, so the touchpad path is checked
    // through the same scrollBy the handler calls with them.
    function test_touchpadPixelsAreOneToOne() {
      handler.scrollBy(-37)
      compare(list.contentY - list.originY, 37)
    }

    function test_touchpadScaleIsApplied() {
      handler.touchpadScale = 2.5
      handler.touchpad(-10, Qt.ScrollUpdate)
      handler.touchpadScale = 1
      compare(list.contentY - list.originY, 25)
      handler.release()
    }

    // A quick swipe keeps coasting the same way after the fingers lift.
    function test_flickCoastsAfterRelease() {
      for (var i = 0; i < 6; i++) { handler.touchpad(-12, Qt.ScrollUpdate); wait(16) }
      var lifted = list.contentY
      handler.touchpad(0, Qt.ScrollEnd)
      verify(list.flicking, "coasting started")
      wait(150)
      verify(list.contentY > lifted + 10, "kept moving down: " + lifted + " -> " + list.contentY)
      list.cancelFlick()
    }

    // Fingers that stop before lifting leave the list where it is.
    function test_slowReleaseDoesNotCoast() {
      handler.touchpad(-5, Qt.ScrollUpdate)
      wait(200)
      handler.touchpad(0, Qt.ScrollEnd)
      verify(!list.flicking)
    }

    function test_stopsAtBothEnds() {
      mouseWheel(list, 150, 100, 0, 120)
      compare(list.contentY, list.originY)
      for (var i = 0; i < 40; i++) mouseWheel(list, 150, 100, 0, -120)
      compare(list.contentY, list.originY + list.contentHeight - list.height)
    }
  }
}
