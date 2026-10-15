import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "slylem0.display-switch"

  property bool alive: true
  property bool busy: false
  property var status: Model.emptyState()
  readonly property string lang: Model.language(setting("language", "auto"), Qt.locale().name)
  readonly property string pluginPath: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string helper: pluginPath + "/bin/display-switch"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  // Changing a monitor rule reloads Hyprland, which can tear down the bar this
  // widget lives on (e.g. "second screen only" disables the laptop panel).
  // Detached runs keep the helper alive through that; state is re-read after.
  function run(args) {
    Quickshell.execDetached(["env", "DISPLAY_SWITCH_LANG=" + root.lang, root.helper].concat(args))
    root.busy = true
    settle.restart()
  }

  function setMode(mode) { run([mode]) }
  function cycleMode() { run(["cycle"]) }
  function setPosition(position) { run(["position", position]) }
  function rotate(output, transform) { run(["rotate", output, String(transform)]) }
  function setScale(output, scale) { run(["scale", output, String(scale)]) }

  // Brightness does not reload Hyprland, so it runs attached and in order:
  // while one change is in flight only the latest requested level is kept.
  property var pendingBrightness: null
  function setBrightness(output, level) {
    var value = Model.clamp(level, 1, 100)
    patchMonitor(output, { brightness: value })
    pendingBrightness = { output: output, level: value }
    if (!brightnessProcess.running) flushBrightness()
  }
  function flushBrightness() {
    if (!pendingBrightness) return
    brightnessProcess.command = [root.helper, "brightness", pendingBrightness.output, String(pendingBrightness.level)]
    pendingBrightness = null
    brightnessProcess.running = true
  }

  // Show a change right away instead of waiting for the next state read.
  function patchMonitor(output, fields) {
    var next = JSON.parse(JSON.stringify(root.status))
    for (var i = 0; i < next.monitors.length; i++) {
      if (next.monitors[i].name !== output) continue
      for (var key in fields) next.monitors[i][key] = fields[key]
    }
    root.status = next
  }

  function setTextSize(px) {
    Quickshell.execDetached(["omarchy-display-text-size", String(px)])
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Component.onCompleted: {
    Quickshell.execDetached([root.helper, "sync"])
    refresh()
  }

  // Re-apply the remembered mode and per-device rotation when a display is
  // plugged in or removed. The helper ignores events where the set of devices
  // did not change, so the reload it triggers does not loop back here.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name.indexOf("monitoradded") === 0 || name.indexOf("monitorremoved") === 0) hotplug.restart()
    }
  }

  Timer {
    id: hotplug
    interval: 1500
    onTriggered: root.run(["sync"])
  }

  Timer {
    id: settle
    interval: 1500
    onTriggered: {
      root.busy = false
      root.refresh()
    }
  }

  Timer {
    interval: 4000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Process {
    id: stateProcess
    command: [root.helper, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.alive) return
        // Keep a level the user just picked until the helper has stored it.
        if (brightnessProcess.running || root.pendingBrightness) return
        root.status = Model.parseState(text)
        var unknown = root.status.monitors.some(function(m) { return m.enabled && m.brightnessBackend === "unknown" })
        if (unknown && !probeProcess.running) probeProcess.running = true
      }
    }
  }

  // Finds out once per display whether it has hardware brightness control.
  // A display without DDC/CI can take several seconds to answer.
  Process {
    id: probeProcess
    command: [root.helper, "probe"]
    onRunningChanged: if (!running && root.alive) root.refresh()
  }

  Process {
    id: brightnessProcess
    onRunningChanged: {
      if (running || !root.alive) return
      if (root.pendingBrightness) root.flushBrightness()
      else root.refresh()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.modeIcon(root.status.mode)
    tooltipText: Model.tr(root.lang, "tooltip") + Model.modeLabel(root.lang, root.status.mode)
      + (root.status.hasExternal ? "\n" + Model.tr(root.lang, "tooltipCycle") : "")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton && root.status.hasExternal) root.cycleMode()
      else root.toggle()
    }
  }

  Component.onDestruction: {
    alive = false
    stateProcess.running = false
    probeProcess.running = false
  }
}
