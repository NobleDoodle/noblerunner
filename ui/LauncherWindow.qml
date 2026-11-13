import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../core/Commands.js" as Commands
import "../core/RootSearch.js" as RootSearch
import "../core/Rows.js" as Rows
import "FontScale.js" as FontScale

// Omarchy 4.0.x dropped qs.Ui.OverlayWindow; this is the same full-screen
// overlay layer the shell's own emoji picker uses.
PanelWindow {
  id: window

  required property var backend
  property var appLibrary: null
  property bool shown: false
  readonly property bool busy: window.shown && window.backend.loading
  readonly property int loadingFeedbackDelay: 500
  property bool loadingVisible: false

  onBusyChanged: {
    window.loadingVisible = false
    if (window.busy) loadingDelay.restart()
    else loadingDelay.stop()
  }

  Timer {
    id: loadingDelay
    interval: window.loadingFeedbackDelay
    onTriggered: window.loadingVisible = window.busy
  }

  signal dismissRequested()

  // The layer is not a window, so Superwhisper's edge glow would sit on
  // whatever was focused behind it. A borderless toplevel (title
  // noblerunner-glow, floated by the glowRule below) is focused first and then
  // kept on the card. The real glow follows that window. The Hyprland
  // binds still start and stop dictation; calling record from here would
  // toggle it off again.
  property bool anchorUp: false
  property bool layerUp: false
  property string restoreAddress: ""
  property string anchorSent: ""

  function anchorAddressOk(addr) {
    return /^0x[0-9a-f]+$/i.test(String(addr || ""))
  }
  function anchorMonitor() {
    if (window.screen) {
      var via = Hyprland.monitorFor(window.screen)
      if (via && via.width > 0) return via
    }
    return Hyprland.focusedMonitor
  }
  // The panel is not fullscreen until it is mapped, and its card is then
  // only as wide as that small window. Size the glow from the real card
  // once the layer is up, and from the same width formula before that.
  // Property reads stay in the binding: a function call would not track them.
  // While the card is moving, leave the glow size alone. Resizing that
  // toplevel on every frame is what made the open look like it was stepping.
  readonly property bool cardMoving: (expand > 0.004 && expand < 0.996) || (slide > 0.004 && slide < 0.996)
  readonly property int glowW: Math.max(1, (layerUp && !cardMoving && width > 400 && card.width > 40) ? Math.round(card.width) : Math.round(px(525)))
  // Superwhisper paints the bottom fifth of this window. Twice the bar
  // height makes that band twice as tall. The bottom stays on the card.
  readonly property int glowH: Math.max(1, Math.round(card.collapsedHeight * 2))
  function anchorRect() {
    var mon = window.anchorMonitor()
    var ox = mon ? mon.x : 0
    var oy = mon ? mon.y : 0
    if (window.layerUp && window.width > 400 && card.width > 40) {
      var wCard = Math.round(card.width)
      var bottom = oy + Math.round(card.y + card.height)
      return { x: ox + Math.round(card.x), y: bottom - window.glowH, w: wCard, h: window.glowH }
    }
    var w = window.glowW
    var h = window.glowH
    var mw = mon && mon.width > 0 ? mon.width : 1920
    var mh = mon && mon.height > 0 ? mon.height : 1080
    return {
      x: ox + Math.round((mw - w) / 2),
      y: oy + Math.max(0, Math.round((mh - h) / 2)),
      w: w,
      h: h
    }
  }
  function findAnchor() {
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].title === "noblerunner-glow") return list[i]
    }
    return null
  }
  // Hyprland centers a new float in the work area, under the bar. That is
  // 21px below the card, so the glow (the window's bottom edge) sits under
  // the border. Move with hyprctl until the reported position is the card.
  property string anchorPlacedKey: ""
  property string anchorWant: ""
  property string anchorTryKey: ""
  property int anchorTries: 0
  readonly property string anchorScript:
    "import json,subprocess,sys\n"
    + "x,y,w,h=map(int,sys.argv[1:5])\n"
    + "cs=json.loads(subprocess.check_output(['hyprctl','clients','-j']))\n"
    + "g=next((c for c in cs if c.get('title')=='noblerunner-glow' or c.get('initialTitle')=='noblerunner-glow'), None)\n"
    + "if not g:\n"
    + " print('missing'); raise SystemExit\n"
    + "at=g.get('at') or [0,0]\n"
    + "size=g.get('size') or [0,0]\n"
    + "addr=g['address']\n"
    + "if int(size[0])!=w or int(size[1])!=h:\n"
    + " subprocess.check_call(['hyprctl','dispatch','hl.dsp.window.resize({ x = %d, y = %d, relative = false, window = \"address:%s\" })'%(w,h,addr)])\n"
    + "if int(at[0])!=x or int(at[1])!=y or int(size[0])!=w or int(size[1])!=h:\n"
    + " subprocess.check_call(['hyprctl','dispatch','hl.dsp.window.move({ x = %d, y = %d, relative = false, window = \"address:%s\" })'%(x,y,addr)])\n"
    + " print('moved'); raise SystemExit\n"
    + "print('placed')\n"
  function placeAnchor() {
    if (!window.anchorUp || window.cardMoving || anchorMover.running) return
    var rect = window.anchorRect()
    var key = rect.x + "," + rect.y + "," + rect.w + "," + rect.h
    if (key === window.anchorPlacedKey) return
    if (key !== window.anchorTryKey) { window.anchorTryKey = key; window.anchorTries = 0 }
    if (window.anchorTries > 8) return
    window.anchorWant = key
    anchorMover.command = ["/usr/bin/python3", "-c", window.anchorScript, String(rect.x), String(rect.y), String(rect.w), String(rect.h)]
    anchorMover.running = true
  }
  function focusAnchor(top) {
    if (!top || !window.anchorAddressOk(top.address)) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + top.address + '" })')
  }
  function syncAnchor() {
    if (!window.anchorUp) return
    window.anchorPlacedKey = ""
    window.placeAnchor()
  }
  // The toplevel is only worth its focus change when Superwhisper is there
  // to draw on it. The rule keeps Hyprland from decorating it: a border or
  // blur box would show around the card's bottom edge. Runtime rules are
  // dropped by a config reload, so it is sent again after one.
  property bool glowAvailable: false
  readonly property bool glowWanted: window.glowAvailable && window.backend.config.superwhisperGlow
  onGlowWantedChanged: if (window.glowWanted) glowRule.running = true
  Process {
    id: glowProbe
    command: ["sh", "-c", "command -v superwhisper >/dev/null 2>&1"]
    onExited: function(exitCode) { window.glowAvailable = exitCode === 0 }
  }
  Process {
    id: glowRule
    command: ["hyprctl", "eval", 'hl.window_rule({ match = { title = "^noblerunner-glow$" }, float = true, decorate = false, no_shadow = true, no_anim = true, no_blur = true, border_size = 0, rounding = 0 })']
  }
  // Hyprland blurs a layer only when a rule says so. With this one a
  // see-through card (menu.background-alpha below 1) shows blur behind it,
  // as the Omarchy menu does on a setup that blurs it; an opaque card looks
  // the same either way. ignore_alpha leaves the clear surround alone.
  Process {
    id: blurRule
    command: ["hyprctl", "eval", 'hl.layer_rule({ match = { namespace = "^noblerunner$" }, blur = true, ignore_alpha = 0.75 })']
  }
  function raiseAnchor() {
    if (!window.glowWanted) { window.layerUp = true; return }
    var current = Hyprland.activeToplevel
    if (current && window.anchorAddressOk(current.address) && current.title !== "noblerunner-glow")
      window.restoreAddress = current.address
    window.anchorSent = ""
    window.anchorPlacedKey = ""
    window.anchorTryKey = ""
    window.anchorTries = 0
    window.anchorUp = true
    anchorPoll.tries = 0
    anchorPoll.restart()
  }
  function dropAnchor() {
    anchorPoll.stop()
    var addr = window.restoreAddress
    window.restoreAddress = ""
    window.anchorSent = ""
    window.anchorPlacedKey = ""
    window.anchorUp = false
    window.layerUp = false
    if (!window.anchorAddressOk(addr)) return
    Qt.callLater(function() {
      Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
    })
  }

  visible: window.layerUp
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "noblerunner"
  WlrLayershell.layer: WlrLayer.Overlay
  // Closing keeps the layer mapped for the slide. Exclusive focus and a full
  // input region would leave the desktop unable to take a click or a key.
  WlrLayershell.keyboardFocus: window.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
  mask: Region { item: window.closing ? null : clickSurface }

  readonly property var general: {
    window.backend.storeRevision
    var r = window.backend.ready ? window.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({ uiZoom: 1, windowMode: "expanded", escapeKeyBehavior: "pop-back-or-close", popToRootTimeout: 90, navigationBindings: "emacs", animationSpeed: 1 })
  }
  readonly property real zoom: window.general.uiZoom > 0 ? window.general.uiZoom : 1
  function px(value) { return Math.round(Style.space(value) * window.zoom) }

  readonly property var look: ({
    background: Commons.Color.menu.background,
    foreground: Commons.Color.menu.text,
    accent: Commons.Color.menu.selectedText,
    selectedBackground: Commons.Color.menu.selectedBackground,
    fontFamily: Style.font.menuFamily
  })
  // Live window chrome: decoration:rounding (Style.cornerRadius), general:border_size,
  // and general:col.active_border. Refreshed when Hyprland reloads its config.
  property int windowBorderSize: 2
  property string windowBorderGradient: ""
  function hyprHex(token) {
    var s = String(token || "").replace(/^#/, "").replace(/^0x/i, "")
    if (/^[0-9A-Fa-f]{6}$/.test(s)) return "#ff" + s
    if (/^[0-9A-Fa-f]{8}$/.test(s)) return "#" + s
    return ""
  }
  readonly property var borderSpec: {
    var raw = String(window.windowBorderGradient || "")
    var width = window.windowBorderSize
    if (raw.length === 0) return Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
    var parts = raw.trim().split(/\s+/)
    var colors = []
    var angle = 0
    for (var i = 0; i < parts.length; i++) {
      if (/^-?\d+(?:\.\d+)?deg$/.test(parts[i])) angle = Number(parts[i].replace(/deg$/, ""))
      else {
        var color = window.hyprHex(parts[i])
        if (color.length > 0) colors.push(color)
      }
    }
    if (colors.length === 0) return Border.flat(Commons.Color.menu.border, width)
    return {
      color: colors[0],
      widths: { top: width, right: width, bottom: width, left: width },
      gradient: { colors: colors, angle: angle, enabled: colors.length > 1 }
    }
  }
  function refreshWindowBorder() {
    borderSizeProc.running = true
    borderColorProc.running = true
  }

  Process {
    id: borderSizeProc
    command: ["hyprctl", "-j", "getoption", "general:border_size"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var n = Number(JSON.parse(text || "{}").int)
          if (isFinite(n) && n >= 0) window.windowBorderSize = n
        } catch (e) {}
      }
    }
  }
  Process {
    id: borderColorProc
    command: ["hyprctl", "-j", "getoption", "general:col.active_border"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var gradient = String(JSON.parse(text || "{}").gradient || "")
          if (gradient.length > 0) window.windowBorderGradient = gradient
        } catch (e) {}
      }
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "configreloaded") return
      window.refreshWindowBorder()
      blurRule.running = true
      if (window.glowWanted) glowRule.running = true
    }
  }
  Component.onCompleted: {
    window.refreshWindowBorder()
    blurRule.running = true
    glowProbe.running = true
  }

  property var stack: [{ kind: "root", title: "noblerunner", query: "" }]
  readonly property var view: window.stack[window.stack.length - 1]
  property string query: ""
  onQueryChanged: if (queryText && queryText.text !== window.query) queryText.text = window.query
  // Query the rows currently on screen were built for. An empty-root catalog
  // must not flash in the panel that opens for the first character.
  property string rowsQuery: ""
  // Keep the rows on screen while the next answer is in flight when the query
  // only grew or shrank. Hiding them on backspace redraws the same list.
  readonly property bool rowsForQuery: {
    if (window.rowsQuery === window.query) return true
    var shown = String(window.rowsQuery)
    var next = String(window.query)
    if (!shown || !next) return false
    return shown.indexOf(next) === 0 || next.indexOf(shown) === 0
  }
  // 0 turns motion off. 1 is the normal length. 2 is twice as fast.
  function motion(ms) {
    var speed = Number(window.general.animationSpeed)
    if (!isFinite(speed) || speed <= 0) return 0
    return Style.duration(Math.max(1, Math.round(ms / speed)))
  }
  property bool cardAnimate: true
  // True while the card is sliding off the bottom. The layer stays mapped
  // until that animation ends.
  property bool closing: false
  // 0 is just below the screen, 1 is the resting (centered) position.
  property real slide: 0
  Behavior on slide {
    enabled: window.cardAnimate
    NumberAnimation {
      id: slideAnim
      duration: window.motion(380)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
      // finished, not stopped: a Behavior emits stopped when a new slide
      // interrupts it, which is still mid-way, and finished when it arrives.
      onFinished: if (window.closing) window.finishClose()
    }
  }
  property int selectedIndex: -1
  property var selectedRow: null
  property int searchSerial: 0
  property bool searchPending: false
  property bool actionPanelOpen: false
  property var actions: []
  property var toast: null
  property int historyIndex: -1

  // Ctrl+P root filter (RootSearch.FILTERS), Ctrl+T toast actions,
  // Ctrl+Shift+K About panel and the confirm alert.
  property string rootFilter: "all"
  property bool dropdownOpen: false
  property bool toastPanelOpen: false
  property bool aboutOpen: false
  property var aboutRows: []
  property var alert: null

  // Inline argument pills for the selected command: argFocus -1 is the
  // search field, 0.. an argument.
  property var argDefs: []
  property var argValues: ({})
  property int argFocus: -1
  property string argsForId: ""

  // Navigation bindings (ref 04 §2.8): emacs moves with Ctrl+N (Ctrl+P is the
  // dropdown); vim-motions with Ctrl+J/K, which moves the action panel to
  // Alt+K. Ctrl+B/F and Ctrl+H/L move a text cursor in Raycast; our search
  // field has none, so they do nothing here. [D]
  readonly property bool vim: window.general.navigationBindings === "vim-motions"
  readonly property bool atRoot: window.stack.length === 1
  readonly property bool settingsOpen: window.atRoot && Commands.isSettingsQuery(window.query)
  // Compact is only the search bar until there is a query. Expanded keeps
  // the full list up, including the empty-root catalog.
  readonly property bool compact: window.general.windowMode !== "expanded"
    && window.atRoot && String(window.query || "").trim().length === 0
    && !window.dropdownOpen && !window.actionPanelOpen && !window.aboutOpen
    && !window.toastPanelOpen && !window.alert
  // One real, 0 to 1. Height and position are derived from it, so the open
  // is a single animation instead of a layout pass on every pixel.
  property real expand: window.compact ? 0 : 1
  Behavior on expand {
    enabled: window.cardAnimate
    NumberAnimation {
      duration: window.motion(180)
      easing.type: Easing.Bezier
      easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }
  }
  readonly property string placeholder: window.view.kind === "alias" ? "Type an alias, then press ↵"
    : window.view.kind === "menu" ? "Search " + window.view.title + "…"
    : window.view.kind === "calculator-history" ? "Search calculations…"
    : "Search for apps and commands…"

  readonly property int cardWidth: Math.min(px(525), width - Style.gapsOut * 2)
  readonly property int fullHeight: Math.min(px(475), height - Style.gapsOut * 2)
  readonly property int headerHeight: px(66)
  readonly property int footerHeight: px(42)

  ListModel { id: rows }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }


  onSettingsOpenChanged: if (window.settingsOpen) window.closePopups()

  function applySetting(key, value) {
    if (key === "uiZoom") { window.setZoom(value); return }
    var patch = {}
    patch[key] = value
    window.backend.callSync("settings.updateGeneralSettings", patch)
  }

  function closePopups() {
    window.actionPanelOpen = false
    window.dropdownOpen = false
    window.toastPanelOpen = false
    window.aboutOpen = false
    window.alert = null
  }

  function prepare(payload) {
    // The shell indexes icon files once, at start. An icon theme rebuilt
    // since then (Omarchroma writes a new hashed folder) leaves stale paths
    // and blank icons. Omarchy's menu and app grid rescan on every open; the
    // scan runs in the background and the rows pick up the new paths.
    if (window.appLibrary) window.appLibrary.refreshIcons()
    if (typeof payload.query === "string") window.query = payload.query
    window.closePopups()
    window.historyIndex = -1
    window.rebuild(true)
    Qt.callLater(function() { queryText.forceActiveFocus() })
  }

  function finishClose() {
    if (window.shown) return
    closeWatch.stop()
    var done = !window.closing && !window.layerUp
    window.closing = false
    if (done) return
    if (window.layerUp) window.dropAnchor()
    // Every open starts at the root (onShownChanged), so nothing is kept
    // while hidden: the query and its rows go now.
    window.popToRoot()
  }

  function beginClose() {
    window.searchSerial++
    window.backend.cancelSearch()
    window.searchPending = false
    window.closePopups()
    window.closing = true
    // The card is still on screen for the slide, but the layer must not keep
    // the keyboard or the pointer. The glow toplevel would otherwise stay the
    // active window, so clicks never focus anything underneath.
    anchorPoll.stop()
    window.anchorUp = false
    var addr = window.restoreAddress
    if (window.anchorAddressOk(addr)) {
      Qt.callLater(function() {
        if (window.shown) return
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
      })
    }
    // Already parked under the screen, or the layer is not up: nothing to slide.
    if (!window.layerUp || window.slide === 0) {
      window.finishClose()
      return
    }
    closeWatch.interval = Math.max(1, window.motion(420))
    closeWatch.restart()
    window.slide = 0
  }

  onShownChanged: {
    if (window.shown) {
      // Snap to the bar, parked under the screen, then slide up to center.
      window.closing = false
      window.cardAnimate = false
      window.slide = 0
      window.popToRoot()
      window.closePopups()
      window.cardAnimate = true
      window.raiseAnchor()
      // Reopening while the previous close is still mapped does not change
      // layerUp, so the slide-up has to be asked for here too.
      Qt.callLater(function() {
        if (!window.shown || !window.layerUp) return
        window.slide = 1
        queryText.forceActiveFocus()
      })
      return
    }
    window.beginClose()
  }

  Timer {
    id: closeWatch
    interval: 450
    onTriggered: if (!window.shown) window.finishClose()
  }

  onLayerUpChanged: {
    if (!window.layerUp || !window.shown) return
    Qt.callLater(function() {
      if (!window.shown) return
      window.slide = 1
      queryText.forceActiveFocus()
      window.syncAnchor()
    })
  }

  // Card motion (open, expand, collapse) keeps the glow window on the card.
  readonly property string anchorBox: Math.round(card.x) + "," + Math.round(card.y) + "," + Math.round(card.width) + "," + Math.round(card.height)
  onAnchorBoxChanged: if (window.layerUp && window.anchorUp) window.syncAnchor()

  Timer {
    id: anchorPoll
    interval: 50
    repeat: true
    property int tries: 0
    onTriggered: {
      if (!window.shown || !window.anchorUp) { stop(); return }
      tries++
      var top = window.findAnchor()
      if (top && !window.layerUp) {
        window.focusAnchor(top)
        window.layerUp = true
      } else if (!window.layerUp && tries > 15) {
        window.layerUp = true
      }
      window.placeAnchor()
    }
  }

  Process {
    id: anchorMover
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line)
        if (text.indexOf("placed") !== -1) window.anchorPlacedKey = window.anchorWant
        else if (text.indexOf("moved") !== -1) window.anchorTries++
      }
    }
  }

  FloatingWindow {
    id: glowAnchor
    title: "noblerunner-glow"
    color: "transparent"
    visible: window.anchorUp
    // width, not only implicitWidth: the client size is what Hyprland keeps.
    width: window.glowW
    height: window.glowH
    implicitWidth: window.glowW
    implicitHeight: window.glowH
    minimumSize: Qt.size(window.glowW, window.glowH)
    maximumSize: Qt.size(window.glowW, window.glowH)
    Item { anchors.fill: parent }
  }

  function popToRoot() {
    window.stack = [{ kind: "root", title: "noblerunner", query: "" }]
    window.query = ""
    window.rootFilter = "all"
    window.rebuild(true)
  }


  function push(next) {
    var saved = window.stack.slice()
    saved[saved.length - 1] = Object.assign({}, window.view, { query: window.query, selectedIndex: window.selectedIndex })
    window.stack = saved.concat([next])
    window.query = next.kind === "alias" ? (next.value || "") : ""
    window.rebuild(true)
  }

  function pop() {
    if (window.atRoot) return
    var next = window.stack.slice(0, -1)
    var top = next[next.length - 1]
    window.stack = next
    window.query = top.query || ""
    window.rebuild(false, top.selectedIndex)
  }


  function rebuild(resetSelection, restoreIndex) {
    var serial = ++window.searchSerial
    window.backend.cancelSearch()
    pointerGate.reset()
    var keepId = !resetSelection && window.selectedRow ? window.selectedRow.itemId : ""
    window.searchPending = false
    if (window.view.kind === "alias") { Rows.update(rows, []); window.rowsQuery = window.query; window.select(-1); return }
    if (window.settingsOpen) { window.rowsQuery = window.query; return }
    window.searchPending = true
    var revision = window.backend.candidatesRevision
    window.backend.searchAsync({ query: window.query, view: window.view, filter: window.atRoot ? window.rootFilter : "all" }, function(result) {
      if (serial !== window.searchSerial || revision !== window.backend.candidatesRevision) return
      window.applySearch(result, keepId, restoreIndex)
      window.searchPending = false
    })
  }

  function applySearch(result, keepId, restoreIndex) {
    if (!result.ok) {
      Rows.update(rows, [])
      window.rowsQuery = window.query
      window.showToast("failure", result.error)
      window.select(-1)
      return
    }
    var keepIndex = -1, next = []
    for (var s = 0; s < result.data.length; s++) {
      var section = result.data[s]
      if (section.title || s > 0) next.push(window.rowData({ id: "section:" + section.id, title: section.title }, "section"))
      for (var r = 0; r < section.rows.length; r++) {
        var c = section.rows[r]
        if (c.id === keepId) keepIndex = next.length
        next.push(window.rowData(c, c.kind === "calculator" ? "calculator" : "item"))
      }
    }
    Rows.update(rows, next)
    window.rowsQuery = window.query
    if (restoreIndex >= 0 && restoreIndex < rows.count && window.isSelectable(restoreIndex)) window.select(restoreIndex)
    else window.select(keepIndex >= 0 ? keepIndex : window.nextSelectable(-1, 1))
  }

  function rowData(c, kind) {
    return {
      rowKind: kind,
      itemId: String(c.id || ""),
      title: String(c.title || ""),
      subtitle: String(c.subtitle || ""),
      glyph: String(c.glyph || ""),
      glyphFont: String(c.glyphFont || ""),
      iconName: String(c.iconName || ""),
      typeLabel: String(c.typeLabel || ""),
      alias: String(c.alias || ""),
      checked: !!c.checked,
      disabled: !!c.disabled,
      favorite: typeof c.favoriteOrder === "number",
      calcInput: String(c.calcInput || ""),
      calcResult: String(c.calcResult || ""),
      calcInputCaption: String(c.calcInputCaption || ""),
      calcResultCaption: String(c.calcResultCaption || ""),
      argsJson: JSON.stringify(c.arguments || [])
    }
  }

  function isSelectable(index) {
    var kind = rows.get(index).rowKind
    return kind === "item" || kind === "calculator"
  }

  function nextSelectable(from, direction) {
    for (var i = from + direction; i >= 0 && i < rows.count; i += direction)
      if (window.isSelectable(i)) return i
    return -1
  }

  function select(index) {
    if (index !== window.selectedIndex) {
      var previous = list.itemAtIndex(window.selectedIndex)
      if (previous) previous.selected = false
    }
    window.selectedIndex = index
    var current = list.itemAtIndex(index)
    if (current) current.selected = true
    window.selectedRow = Rows.snapshot(rows, index)
    // Argument values belong to one command; a different row starts empty.
    var id = window.selectedRow ? window.selectedRow.itemId : ""
    if (id !== window.argsForId) {
      window.argsForId = id
      window.argValues = ({})
      window.argFocus = -1
    }
    window.argDefs = window.selectedRow && window.selectedRow.argsJson ? JSON.parse(window.selectedRow.argsJson) : []
    if (index >= 0) list.positionViewAtIndex(index, ListView.Contain)
    if (index === window.nextSelectable(-1, 1)) list.positionViewAtBeginning()
  }

  function move(delta) {
    pointerGate.reset()
    if (window.selectedIndex < 0) { window.select(window.nextSelectable(-1, 1)); return }
    var step = delta > 0 ? 1 : -1
    var target = window.selectedIndex
    for (var n = 0; n < Math.abs(delta); n++) {
      var next = window.nextSelectable(target, step)
      if (next < 0) break
      target = next
    }
    window.select(target)
  }

  function jumpSection(direction) {
    var i = window.selectedIndex
    for (i += direction; i >= 0 && i < rows.count; i += direction)
      if (rows.get(i).rowKind === "section") break
    if (direction < 0) {
      for (i -= 1; i >= 0; i--) if (rows.get(i).rowKind === "section") break
    }
    var first = window.nextSelectable(Math.max(-1, i), 1)
    if (first >= 0) window.select(first)
  }

  function nthItem(n) {
    var seen = 0
    for (var i = 0; i < rows.count; i++) {
      if (!window.isSelectable(i)) continue
      if (++seen === n) return i
    }
    return -1
  }


  function actionsForSelected() {
    if (window.searchPending || !window.selectedRow) return []
    var r = window.backend.callSync("rootSearch.getActions", { id: window.selectedRow.itemId })
    return r.ok ? r.data : []
  }

  function perform(actionId, index) {
    if (window.searchPending) return
    if (index !== undefined && index >= 0) window.select(index)
    if (!window.selectedRow) return
    window.actionPanelOpen = false
    // ↵ on a command with an empty required argument focuses that pill.
    if (actionId === "open" && window.argDefs.length) {
      var missing = RootSearch.missingArgument(window.argDefs, window.argValues)
      if (missing >= 0) { window.argFocus = missing; return }
    }
    window.request({ id: window.selectedRow.itemId, action: actionId, query: window.query, arguments: window.argValues })
  }

  function request(payload) {
    var r = window.backend.callSync("rootSearch.performAction", payload)
    if (!r.ok) { window.showToast("failure", r.error); return }
    var outcome = r.data || {}
    if (outcome.confirm) { window.alert = { spec: outcome.confirm, payload: payload }; return }
    if (outcome.push) { window.push(outcome.push); return }
    if (outcome.close) {
      if (outcome.hud) window.hud(outcome.hud)
      window.dismissRequested()
      window.argValues = ({})
      window.argFocus = -1
      if (window.atRoot) window.setQuery("")
      return
    }
    if (outcome.toast) window.showToast(outcome.toast.style, outcome.toast.title, outcome.toast.actions)
    window.rebuild(false)
  }

  function confirmAlert() {
    var payload = Object.assign({}, window.alert.payload, { confirmed: true })
    window.alert = null
    window.request(payload)
  }

  function performNth(n) {
    var list = window.actionsForSelected()
    if (list.length > n) window.perform(list[n].id)
  }

  function performIfOffered(actionIds) {
    var list = window.actionsForSelected()
    for (var i = 0; i < list.length; i++) if (actionIds.indexOf(list[i].id) >= 0) { window.perform(list[i].id); return true }
    return false
  }

  function toggleActionPanel() {
    if (window.actionPanelOpen) { window.actionPanelOpen = false; return }
    window.actions = window.actionsForSelected()
    window.actionPanelOpen = window.actions.length > 0
    if (actionPanel.item) actionPanel.item.filter = ""
  }

  function toggleDropdown() {
    if (window.dropdownOpen || !window.atRoot) { window.dropdownOpen = false; return }
    window.dropdownOpen = true
    dropdown.item.filter = ""
    var at = RootSearch.FILTERS.map(function(f) { return f.id }).indexOf(window.rootFilter)
    dropdown.item.selectedIndex = Math.max(0, at)
  }

  function setRootFilter(id) {
    window.dropdownOpen = false
    if (window.rootFilter === id) return
    window.rootFilter = id
    window.rebuild(true)
  }

  function toggleAbout() {
    if (window.aboutOpen || !window.selectedRow) { window.aboutOpen = false; return }
    var r = window.backend.callSync("rootSearch.getItemInfo", { id: window.selectedRow.itemId, query: window.query })
    if (!r.ok) { window.showToast("failure", r.error); return }
    window.aboutRows = r.data
    window.aboutOpen = r.data.length > 0
  }

  function toggleToastPanel() {
    if (window.toastPanelOpen) { window.toastPanelOpen = false; toastTimer.restart(); return }
    if (!window.toast || !window.toast.actions.length) return
    window.toastPanelOpen = true
    toastPanel.item.filter = ""
    toastTimer.stop()
  }

  // A toast action is a copy or a backend call (Backend.performAction's
  // toast.actions), with `done` as the success toast.
  function runToastAction(actionId) {
    var action = (window.toast ? window.toast.actions : []).filter(function(a) { return a.id === actionId })[0]
    window.toastPanelOpen = false
    if (!action) return
    if (action.copy !== undefined) {
      window.backend.copyText(action.copy)
      window.showToast("success", "Copied to Clipboard")
      return
    }
    var r = window.backend.callSync(action.call.method, action.call.data)
    if (!r.ok) { window.showToast("failure", r.error); return }
    window.toast = null
    window.rebuild(false)
    if (action.done) window.showToast("success", action.done)
  }

  // Typing, Tab and Backspace while an argument pill has focus.
  function handleArgumentKey(event, shift) {
    var def = window.argDefs[window.argFocus]
    var value = window.argValues[def.name] || ""
    var key = event.key
    function set(next) {
      var values = Object.assign({}, window.argValues)
      values[def.name] = next
      window.argValues = values
    }
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      var step = shift || key === Qt.Key_Backtab ? -1 : 1
      var next = window.argFocus + step
      window.argFocus = next >= window.argDefs.length ? 0 : next
      return true
    }
    if (key === Qt.Key_Backspace && !value) { window.argFocus--; return true }
    if (Util.editsFilter(event, value)) { set(Util.editedFilter(event, value)); return true }
    if (window.isTyping(event)) { set(value + event.text); return true }
    return false
  }

  function saveAlias() {
    var r = window.backend.callSync("settings.updateCommandSettings", { commandId: window.view.commandId, alias: window.query })
    if (!r.ok) { window.showToast("failure", r.error); return }
    var saved = window.query.trim()
    window.pop()
    window.showToast("success", saved ? "Alias saved" : "Alias removed")
    window.rebuild(false)
  }


  // A failure toast always offers its message to copy (Ctrl+T).
  function showToast(style, title, actions) {
    var list = (actions || []).slice()
    if (style === "failure") list.push({ id: "copy-error", title: "Copy Error Message", copy: String(title || "") })
    window.toastPanelOpen = false
    window.toast = { style: style, title: String(title || ""), actions: list }
    toastTimer.interval = list.length ? 6000 : 2500
    toastTimer.restart()
  }

  Timer {
    id: toastTimer
    interval: 2500
    onTriggered: if (!window.toastPanelOpen) window.toast = null
  }

  function hud(text) {
    Quickshell.execDetached(["omarchy-shell", "osd", "show", JSON.stringify({ icon: "", message: String(text), duration: 1500 })])
  }


  function setQuery(next) {
    if (window.query === next) return
    window.query = next
    window.historyIndex = -1
    window.rebuild(true)
  }

  function pasteClipboard() {
    clipboardInput.clear()
    clipboardInput.paste()
    var text = clipboardInput.text.replace(/[\r\n\u2028\u2029]+/g, " ")
    clipboardInput.clear()
    if (!text) return
    if (window.actionPanelOpen) actionPanel.item.filter += text
    else if (window.argFocus >= 0) {
      var name = window.argDefs[window.argFocus].name
      var values = Object.assign({}, window.argValues)
      values[name] = (values[name] || "") + text
      window.argValues = values
    } else {
      if (window.view.kind === "alias") text = text.replace(/\s/g, "")
      window.setQuery(window.query + text)
    }
  }

  TextEdit {
    id: clipboardInput
    visible: false
    textFormat: TextEdit.PlainText
  }

  function recallHistory(direction) {
    var r = window.backend.callSync("rootSearch.getSearchHistory", null)
    var history = r.ok ? r.data : []
    if (history.length === 0) return false
    var next = Math.max(-1, Math.min(history.length - 1, window.historyIndex + direction))
    if (next === window.historyIndex) return true
    window.query = next < 0 ? "" : history[next]
    window.rebuild(true)
    window.historyIndex = next
    return true
  }

  function setZoom(value) {
    var z = Math.round(Math.max(0.8, Math.min(1.5, value)) * 10) / 10
    window.backend.callSync("settings.updateGeneralSettings", { uiZoom: z })
  }

  function handleEscape(shift) {
    if (window.alert) { window.alert = null; return }
    if (window.aboutOpen) { window.aboutOpen = false; return }
    if (window.dropdownOpen) { window.dropdownOpen = false; return }
    if (window.toastPanelOpen) { window.toggleToastPanel(); return }
    if (window.actionPanelOpen) { window.actionPanelOpen = false; return }
    if (window.argFocus >= 0 && !shift) { window.argFocus = -1; return }
    if (shift) { window.popToRoot(); return }
    if (window.general.escapeKeyBehavior === "close-and-pop-to-root") {
      window.dismissRequested()
      window.popToRoot()
      return
    }
    if (window.query && window.view.kind !== "alias") window.setQuery("")
    else if (!window.atRoot) window.pop()
    else window.dismissRequested()
  }

  // -1 up, 1 down or 0, per the navigation bindings. Ctrl+P only moves up
  // inside popups: in the list it opens the dropdown.
  function direction(event, ctrl, alt, inPopup) {
    var key = event.key
    if (!ctrl && !alt && key === Qt.Key_Down) return 1
    if (!ctrl && !alt && key === Qt.Key_Up) return -1
    if (!ctrl || alt || (event.modifiers & Qt.ShiftModifier)) return 0
    if (window.vim) return key === Qt.Key_J ? 1 : (key === Qt.Key_K ? -1 : 0)
    return key === Qt.Key_N ? 1 : (key === Qt.Key_P && inPopup ? -1 : 0)
  }

  function isActionPanelKey(ctrl, alt, shift, key) {
    if (key !== Qt.Key_K || shift) return false
    return window.vim ? alt && !ctrl : ctrl && !alt
  }

  // Keys for a popup list (action panel, dropdown, toast actions).
  function handlePopupKey(event, panel, ctrl, alt) {
    var dir = window.direction(event, ctrl, alt, true)
    if (dir) { panel.move(dir); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { panel.activateSelected(); return true }
    if (Util.editsFilter(event, panel.filter)) { panel.filter = Util.editedFilter(event, panel.filter); return true }
    if (window.isTyping(event)) { panel.filter += event.text; return true }
    return true
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var key = event.key
    var enter = key === Qt.Key_Return || key === Qt.Key_Enter

    var plainLeft = key === Qt.Key_Left && !ctrl && !alt && (event.modifiers & Qt.MetaModifier) === 0
    if (window.alert) {
      if (key === Qt.Key_Escape || plainLeft) window.alert = null
      else if (enter) window.confirmAlert()
      return true
    }
    if (window.settingsOpen && plainLeft && !shift) { settingsList.cycle(-1); return true }
    if (key === Qt.Key_Escape || plainLeft) { window.handleEscape(shift); return true }
    if (ctrl && (key === Qt.Key_Plus || key === Qt.Key_Equal)) { window.setZoom(window.zoom + 0.1); return true }
    if (ctrl && key === Qt.Key_Minus) { window.setZoom(window.zoom - 0.1); return true }
    if (ctrl && key === Qt.Key_0) { window.setZoom(1); return true }
    if (ctrl && key === Qt.Key_BracketLeft) { window.closePopups(); window.pop(); return true }
    // Ctrl+V, Ctrl+Shift+V (the terminal habit) and Shift+Insert paste.
    var meta = (event.modifiers & Qt.MetaModifier) !== 0
    if ((key === Qt.Key_V && ctrl && !alt && !meta) || (key === Qt.Key_Insert && shift && !ctrl && !alt && !meta)) {
      window.pasteClipboard()
      return true
    }

    if (window.aboutOpen) {
      if (ctrl && shift && key === Qt.Key_K) window.aboutOpen = false
      return true
    }
    if (window.dropdownOpen) {
      if (ctrl && !shift && key === Qt.Key_P) { window.dropdownOpen = false; return true }
      return window.handlePopupKey(event, dropdown.item, ctrl, alt)
    }
    if (window.toastPanelOpen) {
      if (ctrl && key === Qt.Key_T) { window.toggleToastPanel(); return true }
      return window.handlePopupKey(event, toastPanel.item, ctrl, alt)
    }
    if (window.actionPanelOpen) {
      if (window.isActionPanelKey(ctrl, alt, shift, key)) { window.actionPanelOpen = false; return true }
      return window.handlePopupKey(event, actionPanel.item, ctrl, alt)
    }
    if (window.settingsOpen) {
      var settingsDir = window.direction(event, ctrl, alt, true)
      if (settingsDir) { settingsList.move(settingsDir); return true }
      if (enter || (key === Qt.Key_Right && !ctrl && !alt && !shift)) { settingsList.cycle(1); return true }
    }

    if (window.view.kind === "alias") {
      if (enter) { window.saveAlias(); return true }
      if (key === Qt.Key_Space) return true
    } else {
      if (ctrl && shift && key === Qt.Key_K) { window.toggleAbout(); return true }
      if (window.isActionPanelKey(ctrl, alt, shift, key)) { window.toggleActionPanel(); return true }
      if (ctrl && !shift && key === Qt.Key_P) { window.toggleDropdown(); return true }
      if (ctrl && !shift && key === Qt.Key_T) { window.toggleToastPanel(); return true }
      // Shift+Enter opens a new window for apps; Enter focuses an open one.
      if (enter && shift && !ctrl && !alt && window.performIfOffered(["open-new"])) return true
      if (enter && ctrl && shift) { window.performNth(2); return true }
      if (enter && ctrl) { window.performNth(1); return true }
      if (enter) { window.performNth(0); return true }
      if (window.argFocus >= 0 && window.handleArgumentKey(event, shift)) return true
      if (key === Qt.Key_Tab && window.argDefs.length) { window.argFocus = 0; return true }
      if (ctrl && alt && key === Qt.Key_Up) { window.performIfOffered(["favorite-up"]); return true }
      if (ctrl && alt && key === Qt.Key_Down) { window.performIfOffered(["favorite-down"]); return true }
      if (ctrl && key === Qt.Key_Up) { window.jumpSection(-1); return true }
      if (ctrl && key === Qt.Key_Down) { window.jumpSection(1); return true }
      var dir = window.direction(event, ctrl, alt, false)
      if (dir < 0) {
        if (window.atRoot && (window.query === "" || window.historyIndex >= 0) && window.selectedIndex === window.nextSelectable(-1, 1) && window.recallHistory(1)) return true
        window.move(-1); return true
      }
      if (dir > 0) {
        if (window.historyIndex >= 0) { window.recallHistory(-1); return true }
        window.move(1); return true
      }
      if (key === Qt.Key_PageUp) { window.move(-8); return true }
      if (key === Qt.Key_PageDown) { window.move(8); return true }
      if (ctrl && shift && key === Qt.Key_F) { window.performIfOffered(["favorite-add", "favorite-remove"]); return true }
      if (ctrl && shift && key === Qt.Key_C) { window.performIfOffered(["copy-command", "copy-id", "copy-question-answer"]); return true }
      if (ctrl && shift && key === Qt.Key_D) { window.performIfOffered(["delete-all-entries"]); return true }
      if (ctrl && key === Qt.Key_D) { window.performIfOffered(["delete-entry"]); return true }
      if (alt && shift && key === Qt.Key_D) { window.performIfOffered(["disable"]); return true }
      if (ctrl && key >= Qt.Key_1 && key <= Qt.Key_9) {
        var target = window.nthItem(key - Qt.Key_0)
        if (target >= 0) window.perform("open", target)
        return true
      }
    }

    if (Util.editsFilter(event, window.query)) { window.setQuery(Util.editedFilter(event, window.query)); return true }
    if (key === Qt.Key_Backspace && !window.query && !window.atRoot) { window.pop(); return true }
    if (window.isTyping(event)) { window.setQuery(window.query + event.text); return true }
    return false
  }

  function isTyping(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
  }

  Connections {
    target: window.backend
    function onCandidatesRevisionChanged() { if (window.shown && !window.actionPanelOpen && !window.alert) window.rebuild(false) }
    // Exchange rates or zone offsets arrived: re-evaluate a calculation on screen.
    function onCalculatorRevisionChanged() { if (window.shown && !window.actionPanelOpen && window.query) window.rebuild(false) }
  }


  Item { id: clickSurface; anchors.fill: parent }

  MouseArea {
    anchors.fill: parent
    enabled: !window.closing
    onClicked: if (!window.backend.config.keepVisibleOnFocusLoss) window.dismissRequested()
  }

  BorderSurface {
    id: card
    readonly property int collapsedHeight: window.headerHeight + borderTop + borderBottom
    readonly property bool listRevealed: window.expand > 0.04
    width: window.cardWidth
    height: collapsedHeight + (window.fullHeight - collapsedHeight) * window.expand
    radius: Style.cornerRadius
    anchors.horizontalCenter: parent.horizontalCenter
    // restY is vertical center. slide moves the card from just below the
    // screen up to restY. Once it has arrived, restY still follows height,
    // so expanding the list keeps the card centered. Not rounded while it
    // moves: rounding the center made the rise move in visible steps. At
    // rest it sits on a whole pixel, or an odd height difference would leave
    // the top and bottom border half a pixel soft.
    readonly property real restY: {
      var centered = (window.height - height) / 2
      var y = Math.max(Style.gapsOut, Math.min(centered, window.height - height - Style.gapsOut))
      return window.cardMoving ? y : Math.round(y)
    }
    y: restY + (window.height - restY) * (1 - window.slide)
    color: window.look.background
    borderSpec: window.borderSpec
    clip: true

    MouseArea { anchors.fill: parent; onClicked: { window.closePopups(); queryText.forceActiveFocus() } }

    Item {
      id: keyCatcher
      anchors.fill: parent
      // Focus stays on queryText. FilterInput forwards every key here first,
      // and accepts it when handleKey uses it, so it is not typed twice.
      // fcitx5 commits never arrive as keys; the field takes those itself.
      Keys.onPressed: function(event) {
        if (window.handleKey(event)) event.accepted = true
      }
    }

    Item {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: card.borderTop
      anchors.leftMargin: card.borderLeft
      anchors.rightMargin: card.borderRight
      height: window.headerHeight

      Item {
        id: lead
        width: window.px(28)
        height: window.px(28)
        anchors.left: parent.left
        anchors.leftMargin: window.px(18)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: window.atRoot ? "" : ""
          font.family: window.look.fontFamily
          font.pixelSize: FontScale.px(window.atRoot ? window.px(18) : window.px(15))
          color: window.atRoot ? window.look.accent : window.look.foreground
          opacity: window.atRoot ? 1 : 0.7
        }

        MouseArea {
          anchors.fill: parent
          enabled: !window.atRoot
          cursorShape: Qt.PointingHandCursor
          onClicked: window.handleEscape(false)
        }
      }

      // Room left of the filter button; argument pills sit right after the
      // typed text (ref 04 §2.2 WidthSizer).
      readonly property real queryRoom: (filterButton.visible ? filterButton.x - window.px(12) : header.width - window.px(20)) - queryText.x

      FilterInput {
        id: queryText
        x: lead.x + lead.width + window.px(12)
        // An empty field is only a few pixels wide, which clipped the
        // placeholder down to nothing. Use the whole row until there is text.
        width: {
          var room = Math.max(window.px(8), header.queryRoom - (pills.visible ? pills.width + window.px(10) : 0))
          if (!text && !preeditText) return room
          return Math.min(Math.max(implicitWidth, window.px(8)), room)
        }
        anchors.verticalCenter: parent.verticalCenter
        keyHandler: keyCatcher
        color: window.look.foreground
        font.family: window.look.fontFamily
        font.pixelSize: FontScale.px(Style.font.heading * 1.15 * window.zoom)
        onTextChanged: if (text !== window.query) window.setQuery(text)
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: queryText
        verticalAlignment: Text.AlignVCenter
        visible: !window.query && !queryText.preeditText && !pills.visible
        text: window.placeholder
        color: window.look.foreground
        opacity: 0.45
        font.family: window.look.fontFamily
        font.pixelSize: queryText.font.pixelSize
        elide: Text.ElideRight
      }

      Rectangle {
        width: Math.max(1, Style.space(2))
        height: queryText.font.pixelSize + Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        x: queryText.x + (window.query ? Math.min(queryText.contentWidth, queryText.width) + Style.space(1) : 0)
        color: window.look.accent
        visible: window.shown && !window.actionPanelOpen && window.argFocus < 0

        SequentialAnimation on opacity {
          running: window.shown
          loops: Animation.Infinite
          NumberAnimation { to: 1; duration: 0 }
          PauseAnimation { duration: 530 }
          NumberAnimation { to: 0; duration: 0 }
          PauseAnimation { duration: 530 }
        }
      }

      Row {
        id: pills
        visible: window.argDefs.length > 0 && window.view.kind !== "alias"
        x: queryText.x + (window.query ? queryText.width : 0) + window.px(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: window.px(6)

        Repeater {
          model: pills.visible ? window.argDefs : []

          Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property string value: window.argValues[modelData.name] || ""
            readonly property bool focused: window.argFocus === index
            height: window.px(28)
            width: Math.min(window.px(220), pillText.implicitWidth + window.px(20))
            radius: Math.max(Style.cornerRadius, window.px(6))
            color: Util.alpha(window.look.foreground, pill.focused ? 0.12 : 0.06)
            border.width: 1
            border.color: pill.focused ? window.look.accent : Util.alpha(window.look.foreground, 0.15)

            Text {
              id: pillText
              anchors.left: parent.left
              anchors.leftMargin: window.px(10)
              anchors.right: parent.right
              anchors.rightMargin: window.px(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: pill.value || (pill.modelData.placeholder + (pill.modelData.required ? "" : " (optional)"))
              opacity: pill.value ? 1 : 0.5
              color: window.look.foreground
              elide: Text.ElideLeft
              font.family: window.look.fontFamily
              font.pixelSize: FontScale.px(Style.font.body * window.zoom)
            }

            Rectangle {
              visible: pill.focused && window.shown
              width: Math.max(1, Style.space(2))
              height: pillText.font.pixelSize + Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              x: pillText.x + (pill.value ? Math.min(pillText.contentWidth, pillText.width) + Style.space(1) : 0)
              color: window.look.accent
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.IBeamCursor
              onClicked: { window.argFocus = pill.index; queryText.forceActiveFocus() }
            }
          }
        }
      }

      Rectangle {
        id: filterButton
        visible: window.atRoot && !window.compact
        anchors.right: parent.right
        anchors.rightMargin: window.px(16)
        anchors.verticalCenter: parent.verticalCenter
        height: window.px(28)
        width: filterRow.implicitWidth + window.px(20)
        radius: Math.max(Style.cornerRadius, window.px(6))
        color: Util.alpha(window.look.foreground, window.dropdownOpen ? 0.12 : 0.06)
        border.width: 1
        border.color: Util.alpha(window.look.foreground, 0.12)

        Row {
          id: filterRow
          anchors.centerIn: parent
          spacing: window.px(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (RootSearch.FILTERS.filter(function(f) { return f.id === window.rootFilter })[0] || RootSearch.FILTERS[0]).title
            color: window.look.foreground
            opacity: window.rootFilter === "all" ? 0.7 : 1
            font.family: window.look.fontFamily
            font.pixelSize: FontScale.px(Style.font.bodySmall * window.zoom)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "▾"
            color: window.look.foreground
            opacity: 0.6
            font.pixelSize: FontScale.px(Style.font.bodySmall * window.zoom)
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { window.toggleDropdown(); queryText.forceActiveFocus() }
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.spacing.hairline
        color: Util.alpha(window.look.foreground, 0.12)
        visible: card.listRevealed
      }
    }

    Item {
      id: body
      // Fixed at the open height. The card clips it as it grows, so the
      // list does not reflow on every frame of the animation.
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      anchors.leftMargin: card.borderLeft + window.px(8)
      anchors.rightMargin: card.borderRight + window.px(8)
      height: Math.max(0, window.fullHeight - card.collapsedHeight - (footer.live ? window.footerHeight : 0))

      SettingsPanel {
        id: settingsList
        anchors.fill: parent
        visible: window.settingsOpen
        general: window.general
        look: window.look
        zoom: window.zoom
        apply: function(key, value) { window.applySetting(key, value) }
      }

      ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: window.px(4)
        anchors.bottomMargin: window.px(4)
        visible: !window.settingsOpen && window.rowsForQuery && window.view.kind !== "alias"
        clip: true
        model: rows
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll { view: list; lineHeight: window.px(42) }

        delegate: ResultRow {
          Component.onCompleted: selected = index === window.selectedIndex
          ListView.onReused: selected = index === window.selectedIndex
          ListView.onPooled: selected = false
          look: window.look
          appLibrary: window.appLibrary
          zoom: window.zoom
          onHovered: function(i, item, mouse) { if (!window.actionPanelOpen && pointerGate.moved(item, mouse)) window.select(i) }
          onClicked: function(i) { window.perform("open", i) }
        }
      }

      Column {
        anchors.centerIn: parent
        spacing: window.px(8)
        visible: !window.settingsOpen && window.rowsForQuery && (window.view.kind === "alias" || rows.count === 0)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: window.view.kind === "alias" ? "" : ""
          color: window.look.accent
          font.family: window.view.kind === "alias" ? window.look.fontFamily : "omarchy"
          font.pixelSize: FontScale.px(window.px(28))
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: window.view.kind === "alias" ? window.view.title
            : window.view.kind === "calculator-history" && !window.query ? "No Calculations Yet"
            : (window.backend.ready ? "No results" : "Loading…")
          color: window.look.foreground
          font.family: window.look.fontFamily
          font.pixelSize: FontScale.px(Style.font.title * window.zoom)
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: window.view.kind === "alias" ? "Typing the alias exactly in the root search puts this command on top. Leave it empty to remove it."
            : window.view.kind === "calculator-history" && !window.query ? "Type a calculation in the root search, then copy or paste the answer." : ""
          visible: text.length > 0
          color: window.look.foreground
          opacity: 0.55
          font.family: window.look.fontFamily
          font.pixelSize: FontScale.px(Style.font.bodySmall * window.zoom)
        }
      }
    }

    Rectangle {
      id: footer
      // Hidden until a toast or the delayed loading line needs it.
      readonly property bool live: !window.compact && (!!window.toast || window.loadingVisible)
      visible: footer.live
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.borderBottom
      anchors.leftMargin: card.borderLeft
      anchors.rightMargin: card.borderRight
      height: footer.live ? window.footerHeight : 0
      color: Util.alpha(window.look.foreground, 0.04)

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.spacing.hairline
        color: Util.alpha(window.look.foreground, 0.12)
      }

      Row {
        anchors.left: parent.left
        anchors.leftMargin: window.px(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: window.px(8)
        visible: !!window.toast || window.loadingVisible

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: window.toast && window.toast.style === "failure" ? "" : ""
          font.family: window.look.fontFamily
          font.pixelSize: FontScale.px(window.px(12))
          color: window.toast && window.toast.style === "failure" ? "#e06c75" : window.look.accent
          visible: !!window.toast
        }
        Text {
          id: footerStatus
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: window.toast ? window.toast.title : window.loadingVisible ? "Loading…" : window.view.title
          color: window.look.foreground
          opacity: window.toast ? 0.9 : 0.6
          elide: Text.ElideRight
          width: Math.min(implicitWidth, footer.width - window.px(32))
          font.family: window.look.fontFamily
          font.pixelSize: FontScale.px(Style.font.bodySmall * window.zoom)
        }
      }
    }

    Loader {
      id: actionPanel
      active: window.actionPanelOpen
      z: 10
      anchors.right: parent.right
      anchors.rightMargin: card.borderRight + window.px(10)
      anchors.bottom: footer.top
      anchors.bottomMargin: window.px(6)
      sourceComponent: ActionPanel {
        actions: window.actions
        look: window.look
        zoom: window.zoom
        onActivated: function(actionId) { window.perform(actionId) }
      }
    }

    Loader {
      id: dropdown
      active: window.dropdownOpen
      z: 10
      width: window.px(240)
      anchors.right: parent.right
      anchors.rightMargin: card.borderRight + window.px(10)
      anchors.top: header.bottom
      anchors.topMargin: window.px(4)
      sourceComponent: ActionPanel {
        placeholder: "Filter…"
        actions: RootSearch.FILTERS.map(function(f) {
          return { id: f.id, title: f.title, shortcut: "", section: "filter", icon: f.id === window.rootFilter ? "✓" : " " }
        })
        look: window.look
        zoom: window.zoom
        onActivated: function(id) { window.setRootFilter(id) }
      }
    }

    Loader {
      id: toastPanel
      active: window.toastPanelOpen
      z: 10
      width: window.px(280)
      anchors.left: parent.left
      anchors.leftMargin: card.borderLeft + window.px(10)
      anchors.bottom: footer.top
      anchors.bottomMargin: window.px(6)
      sourceComponent: ActionPanel {
        placeholder: "Search toast actions…"
        actions: (window.toast ? window.toast.actions : []).map(function(a) {
          return { id: a.id, title: a.title, shortcut: "", section: "toast", icon: " " }
        })
        look: window.look
        zoom: window.zoom
        onActivated: function(id) { window.runToastAction(id) }
      }
    }

    Loader {
      active: window.aboutOpen
      z: 10
      anchors.right: parent.right
      anchors.rightMargin: card.borderRight + window.px(10)
      anchors.bottom: footer.top
      anchors.bottomMargin: window.px(6)
      sourceComponent: InfoPanel {
        title: window.selectedRow ? window.selectedRow.title : ""
        rows: window.aboutRows
        look: window.look
        zoom: window.zoom
      }
    }

    Loader {
      active: !!window.alert
      z: 20
      anchors.fill: parent
      sourceComponent: Alert {
        spec: window.alert ? window.alert.spec : null
        look: window.look
        zoom: window.zoom
        onConfirmed: window.confirmAlert()
        onCancelled: window.alert = null
      }
    }
  }
}
