import QtQuick
import qs.Commons
import "FontScale.js" as FontScale

// The /settings helper. Up and down move. Right or Enter changes the value.
Item {
  id: panel

  property var general: ({})
  property var look: null
  property real zoom: 1
  property int selectedIndex: 0
  property var apply: null

  function px(v) { return Math.round(Style.space(v) * panel.zoom) }

  readonly property var rows: [
    { key: "windowMode", label: "Window", kind: "choice", choices: ["expanded", "compact"], labels: ["Expanded", "Compact"] },
    { key: "escapeKeyBehavior", label: "Escape", kind: "choice", choices: ["pop-back-or-close", "close-and-pop-to-root"], labels: ["Back out, then close", "Close and return to root"] },
    { key: "navigationBindings", label: "Navigation", kind: "choice", choices: ["emacs", "vim-motions"], labels: ["Emacs", "Vim"] },
    { key: "rootSearchSensitivity", label: "Search sensitivity", kind: "choice", choices: ["low", "medium", "high"], labels: ["Low", "Medium", "High"] },
    { key: "webSearch", label: "Web search", kind: "choice", choices: ["google", "duckduckgo", "brave", "bing", "startpage", "ecosia"], labels: ["Google", "DuckDuckGo", "Brave", "Bing", "Startpage", "Ecosia"] },
    { key: "uiZoom", label: "Zoom", kind: "zoom" },
    { key: "animationSpeed", label: "Animations", kind: "speed", steps: [0, 0.5, 1, 1.5, 2] },
    { key: "popToRootTimeout", label: "Return to root", kind: "seconds" },
    { key: "showFavoritesInCompactMode", label: "Favorites in the bar", kind: "bool" }
  ]

  function move(delta) {
    var n = panel.rows.length
    if (n === 0) return
    panel.selectedIndex = (panel.selectedIndex + delta + n) % n
  }

  function display(row) {
    var value = panel.general ? panel.general[row.key] : undefined
    if (row.kind === "choice") {
      var i = row.choices.indexOf(value)
      return row.labels[i >= 0 ? i : 0]
    }
    if (row.kind === "bool") return value ? "On" : "Off"
    if (row.kind === "zoom") return Math.round((Number(value) || 1) * 100) + "%"
    if (row.kind === "speed") {
      var speed = Number(value)
      if (!isFinite(speed) || speed <= 0) return "Off"
      return (speed === Math.round(speed) ? String(speed) : speed.toFixed(1)) + "×"
    }
    if (row.kind === "seconds") return (Number(value) || 0) + " seconds"
    return value === undefined ? "" : String(value)
  }

  function cycle(dir) {
    var row = panel.rows[panel.selectedIndex]
    if (!row || !panel.apply) return
    var current = panel.general ? panel.general[row.key] : undefined
    if (row.kind === "choice") {
      var i = row.choices.indexOf(current)
      if (i < 0) i = 0
      panel.apply(row.key, row.choices[(i + (dir < 0 ? -1 : 1) + row.choices.length) % row.choices.length])
    } else if (row.kind === "bool") {
      panel.apply(row.key, !current)
    } else if (row.kind === "zoom") {
      var z = Math.round(((Number(current) || 1) + (dir < 0 ? -0.1 : 0.1)) * 10) / 10
      panel.apply(row.key, Math.max(0.8, Math.min(1.5, z)))
    } else if (row.kind === "speed") {
      var steps = row.steps
      var cur = Number(current)
      if (!isFinite(cur)) cur = 1
      var nearest = 0
      for (var s = 1; s < steps.length; s++) if (Math.abs(steps[s] - cur) < Math.abs(steps[nearest] - cur)) nearest = s
      var at = nearest + (dir < 0 ? -1 : 1)
      if (at < 0) at = 0
      if (at >= steps.length) at = steps.length - 1
      panel.apply(row.key, steps[at])
    } else if (row.kind === "seconds") {
      var n = (Number(current) || 0) + (dir < 0 ? -15 : 15)
      panel.apply(row.key, Math.max(0, Math.min(600, n)))
    }
  }

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: panel.px(8)
    spacing: panel.px(2)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Settings"
      color: panel.look.foreground
      font.family: panel.look.fontFamily
      font.pixelSize: FontScale.px(Style.font.body * panel.zoom)
      font.bold: true
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Left and Right change the value"
      color: panel.look.foreground
      opacity: 0.45
      font.family: panel.look.fontFamily
      font.pixelSize: FontScale.px(Style.font.bodySmall * panel.zoom)
      bottomPadding: panel.px(6)
    }

    Repeater {
      model: panel.rows

      Rectangle {
        required property var modelData
        required property int index
        width: content.width
        height: panel.px(36)
        radius: panel.px(6)
        color: index === panel.selectedIndex ? panel.look.selectedBackground : "transparent"

        Row {
          anchors.fill: parent
          anchors.leftMargin: panel.px(10)
          anchors.rightMargin: panel.px(10)
          spacing: panel.px(8)

          Text {
            width: parent.width * 0.52
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: modelData.label
            color: panel.look.foreground
            elide: Text.ElideRight
            font.family: panel.look.fontFamily
            font.pixelSize: FontScale.px(Style.font.body * panel.zoom)
          }
          Text {
            width: parent.width * 0.48 - panel.px(8)
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: panel.display(modelData)
            color: panel.look.accent
            elide: Text.ElideRight
            font.family: panel.look.fontFamily
            font.pixelSize: FontScale.px(Style.font.body * panel.zoom)
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: { panel.selectedIndex = index; panel.cycle(1) }
        }
      }
    }
  }
}
