pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "slylem0.display-switch"
  ipcTarget: "slylem0.display-switch"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var status: hostWidget ? hostWidget.status : Model.emptyState()
  readonly property string lang: hostWidget ? hostWidget.lang : "en"
  readonly property bool busy: hostWidget ? hostWidget.busy : false
  readonly property bool hasExternal: status.hasExternal
  readonly property bool showPosition: hasExternal && status.mode === "extend"
  readonly property var rotatable: status.monitors.filter(function(m) { return m.enabled })
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int inset: Style.space(14)

  // One flat cursor across every interactive row: the four modes, then the
  // position picker (only while extended), then one rotation row per display.
  // j/k walk rows; h/l change the value of a picker row and apply it at once.
  readonly property var rows: {
    var list = []
    for (var i = 0; i < Model.MODES.length; i++) list.push({ type: "mode", value: Model.MODES[i] })
    if (showPosition) list.push({ type: "position" })
    for (var j = 0; j < rotatable.length; j++) list.push({ type: "rotate", name: rotatable[j].name })
    return list
  }
  property int cursorIndex: 0
  property bool cursorActive: false

  function tr(key) { return Model.tr(root.lang, key) }

  function rowIndex(type, name) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].type === type && (name === undefined || rows[i].name === name)) return i
    }
    return -1
  }

  function modeAvailable(mode) { return root.hasExternal || mode === "pc" }

  function open() {
    if (hostWidget) hostWidget.refresh()
    var current = Model.MODES.indexOf(status.mode)
    cursorIndex = current >= 0 ? current : 0
    cursorActive = false
    controller.show()
  }

  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }

  function moveCursor(dy) {
    if (rows.length === 0 || dy === 0) return
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + (dy > 0 ? 1 : -1)))
  }

  function adjust(dx) {
    var row = rows[cursorIndex]
    if (!row || !hostWidget || dx === 0) return
    if (row.type === "position") {
      hostWidget.setPosition(Model.POSITIONS[Model.nextIndex(Model.POSITIONS, status.position, dx > 0 ? 1 : -1)])
    } else if (row.type === "rotate") {
      var monitor = monitorNamed(row.name)
      if (monitor) hostWidget.rotate(monitor.name, Model.ROTATIONS[Model.nextIndex(Model.ROTATIONS, monitor.transform % 4, dx > 0 ? 1 : -1)])
    }
  }

  function selectMode(mode) {
    if (!hostWidget || !modeAvailable(mode)) return
    hostWidget.setMode(mode)
  }

  function activate() {
    var row = rows[cursorIndex]
    if (row && row.type === "mode") selectMode(row.value)
  }

  function monitorNamed(name) {
    for (var i = 0; i < status.monitors.length; i++) if (status.monitors[i].name === name) return status.monitors[i]
    return null
  }

  onRowsChanged: if (cursorIndex > rows.length - 1) cursorIndex = Math.max(0, rows.length - 1)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(20)
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else root.adjust(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var n = parseInt(t, 10)
        if (n >= 1 && n <= Model.MODES.length) root.selectMode(Model.MODES[n - 1])
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: 0

          Item { width: 1; height: Style.space(4) }

          PanelHero {
            width: parent.width
            title: root.tr("title")
            meta: root.busy ? root.tr("applying") : Model.modeLabel(root.lang, root.status.mode)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item { width: 1; height: Style.space(16) }
          PanelSeparator { width: parent.width; foreground: root.foreground }
          Item { width: 1; height: Style.space(10) }

          PanelSectionHeader {
            leftPadding: root.inset
            text: root.tr("project")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item { width: 1; height: Style.space(6) }

          Column {
            id: modeList
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: Model.MODES

              BorderSurface {
                id: modeRow
                required property string modelData
                required property int index
                readonly property bool available: root.modeAvailable(modelData)
                readonly property bool hasCursor: root.cursorActive && root.cursorIndex === index
                readonly property bool current: root.status.mode === modelData
                width: modeList.width
                height: Math.max(Style.space(52), modeContent.implicitHeight + Style.space(20))
                radius: Style.cornerRadius
                opacity: available ? 1 : 0.4
                color: modeArea.pressed && available ? Style.pressedFillFor(root.foreground, root.accent)
                  : hasCursor ? Style.hoverFillFor(root.foreground, root.accent)
                  : current ? Style.selectedFillFor(root.foreground, root.accent)
                  : "transparent"
                borderSpec: hasCursor ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
                  : (current && Border.controlHasWidth("selected")) ? Border.controlSpec("selected", root.foreground, root.accent)
                  : Border.none()

                MouseArea {
                  id: modeArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: modeRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onEntered: { root.cursorActive = true; root.cursorIndex = modeRow.index }
                  onClicked: root.selectMode(modeRow.modelData)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: root.inset
                  anchors.rightMargin: root.inset
                  spacing: Style.spacing.controlGap

                  Text {
                    Layout.preferredWidth: Style.space(28)
                    text: Model.modeIcon(modeRow.modelData)
                    textFormat: Text.PlainText
                    color: modeRow.current ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }

                  ColumnLayout {
                    id: modeContent
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Text {
                      Layout.fillWidth: true
                      text: (modeRow.index + 1) + "  " + root.tr(modeRow.modelData)
                      textFormat: Text.PlainText
                      color: modeRow.current ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: modeRow.current
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: root.tr(modeRow.modelData + "Hint")
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    visible: modeRow.current
                    text: root.tr("current")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                    font.capitalization: Font.AllUppercase
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.showPosition
            spacing: 0

            Item { width: 1; height: Style.space(12) }
            PanelSeparator { width: parent.width; foreground: root.foreground }
            Item { width: 1; height: Style.space(10) }

            PanelSectionHeader {
              leftPadding: root.inset
              text: root.tr("extendTo")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item { width: 1; height: Style.space(8) }

            ButtonGroup {
              id: positionGroup
              readonly property int row: root.rowIndex("position")
              x: root.inset
              spacing: Style.space(6)
              focusable: false
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              value: root.status.position
              options: Model.POSITIONS.map(function(p) { return { value: p, label: root.tr(p) } })
              cursorIndex: root.cursorActive && root.cursorIndex === row ? Model.POSITIONS.indexOf(root.status.position) : -1
              onHovered: function(index, isHovered) { if (isHovered) { root.cursorActive = true; root.cursorIndex = row } }
              onChanged: function(value) { if (root.hostWidget) root.hostWidget.setPosition(value) }
            }
          }

          Item { width: 1; height: Style.space(12) }
          PanelSeparator { width: parent.width; foreground: root.foreground }
          Item { width: 1; height: Style.space(10) }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.controlGap

            PanelSectionHeader {
              Layout.leftMargin: root.inset
              text: root.tr("rotation")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              Layout.fillWidth: true
              Layout.rightMargin: root.inset
              horizontalAlignment: Text.AlignRight
              text: root.tr("rotationHint")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Item { width: 1; height: Style.space(6) }

          Column {
            id: rotationList
            width: parent.width
            spacing: Style.space(10)

            Repeater {
              model: root.rotatable

              Column {
                id: rotationRow
                required property var modelData
                readonly property int row: root.rowIndex("rotate", modelData.name)
                width: rotationList.width
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  leftPadding: root.inset
                  rightPadding: root.inset
                  text: Model.displayName(root.lang, rotationRow.modelData) + "  ·  " + rotationRow.modelData.name
                    + (rotationRow.modelData.mirrorOf !== "none" ? "  →  " + rotationRow.modelData.mirrorOf : "")
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                ButtonGroup {
                  x: root.inset
                  spacing: Style.space(6)
                  focusable: false
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  value: String(rotationRow.modelData.transform % 4)
                  options: Model.ROTATIONS.map(function(t) { return { value: String(t), label: Model.rotationLabel(t) } })
                  cursorIndex: root.cursorActive && root.cursorIndex === rotationRow.row ? rotationRow.modelData.transform % 4 : -1
                  onHovered: function(index, isHovered) { if (isHovered) { root.cursorActive = true; root.cursorIndex = rotationRow.row } }
                  onChanged: function(value) { if (root.hostWidget) root.hostWidget.rotate(rotationRow.modelData.name, Number(value)) }
                }
              }
            }
          }

          Item { width: 1; height: Style.space(14) }

          Text {
            width: parent.width
            leftPadding: root.inset
            rightPadding: root.inset
            text: root.tr("footer")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Item { width: 1; height: Style.space(4) }
        }
      }
    }
  }
}
