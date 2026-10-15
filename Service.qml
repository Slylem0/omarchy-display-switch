import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Software brightness for displays without a backlight or DDC/CI control
// (many portable monitors and projectors). bin/display-switch writes the level
// of each such display to software-brightness.json; this service draws a
// black, click-through layer over that display at the matching opacity.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  property var levels: ({})
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")

  function levelFor(name) {
    var level = root.levels[name]
    return level === undefined ? 100 : level
  }

  FileView {
    id: levelsFile
    path: root.stateHome + "/display-switch/software-brightness.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.levels = Model.parseLevels(text())
    onLoadFailed: root.levels = ({})
  }

  // The file may not exist yet when the shell starts, and a file created later
  // is not always picked up by the watch. Re-reading it is cheap.
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: levelsFile.reload()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      readonly property int level: root.levelFor(modelData.name)

      screen: modelData
      visible: level < 100
      color: Qt.rgba(0, 0, 0, Model.dimOpacity(level))
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "display-switch-dim"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // An empty input region lets every click and scroll through.
      mask: Region {}
    }
  }
}
