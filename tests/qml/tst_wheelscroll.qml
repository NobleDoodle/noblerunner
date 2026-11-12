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
    delegate: Rectangle { width: 300; height: 20 }
    WheelScroll { id: handler; view: list; lineHeight: 20 }
  }

  TestCase {
    name: "WheelScroll"
    when: windowShown

    function init() { list.contentY = list.originY }

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

    function test_stopsAtBothEnds() {
      mouseWheel(list, 150, 100, 0, 120)
      compare(list.contentY, list.originY)
      for (var i = 0; i < 40; i++) mouseWheel(list, 150, 100, 0, -120)
      compare(list.contentY, list.originY + list.contentHeight - list.height)
    }
  }
}
