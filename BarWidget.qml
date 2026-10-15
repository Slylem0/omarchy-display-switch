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
      onStreamFinished: if (root.alive) root.status = Model.parseState(text)
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
  }
}
