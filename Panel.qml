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
  readonly property var displays: status.monitors.filter(function(m) { return m.enabled })
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int inset: Style.space(14)

  // One flat cursor across every interactive row: the four modes, the
  // position picker (only while extended), then brightness, rotation and scale
  // for each display, then text size. j/k walk rows; h/l change the value of a
  // slider or picker row and apply it at once.
  readonly property var rows: {
    var list = []
    for (var i = 0; i < Model.MODES.length; i++) list.push({ type: "mode", value: Model.MODES[i] })
    if (showPosition) list.push({ type: "position" })
    for (var j = 0; j < displays.length; j++) {
      var name = displays[j].name
      if (brightnessAdjustable(displays[j])) list.push({ type: "brightness", name: name })
      list.push({ type: "rotate", name: name })
      if (displays[j].mirrorOf === "none") list.push({ type: "scale", name: name })
    }
    list.push({ type: "textsize" })
    return list
  }
  property int cursorIndex: 0
  property bool cursorActive: false

  // While a text size change lands, show the chosen stop instead of snapping
  // back to the old size.
  property int textSizePending: -1
  readonly property int textSizeIndex: textSizePending >= 0 ? textSizePending : Model.nearestIndex(Model.TEXT_SIZE_STOPS, Style.font.baseSize)

  // Software dimming works by drawing over a screen, which a mirrored output
  // does not have of its own.
  function brightnessAdjustable(monitor) {
    if (!monitor || monitor.brightnessBackend === "unknown") return false
    return !(monitor.brightnessBackend === "software" && monitor.mirrorOf !== "none")
  }

  function brightnessOf(monitor) {
    return monitor && monitor.brightness !== null && monitor.brightness !== undefined ? monitor.brightness : 100
  }

  function setTextSizeIndex(index) {
    var i = Math.max(0, Math.min(Model.TEXT_SIZE_STOPS.length - 1, index))
    textSizePending = i
    textSizeSettle.restart()
    if (hostWidget) hostWidget.setTextSize(Model.TEXT_SIZE_STOPS[i])
  }

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
    } else if (row.type === "textsize") {
      setTextSizeIndex(textSizeIndex + (dx > 0 ? 1 : -1))
    } else {
      var monitor = monitorNamed(row.name)
      if (!monitor) return
      if (row.type === "rotate") {
        hostWidget.rotate(monitor.name, Model.ROTATIONS[Model.nextIndex(Model.ROTATIONS, monitor.transform % 4, dx > 0 ? 1 : -1)])
      } else if (row.type === "brightness") {
        hostWidget.setBrightness(monitor.name, Math.max(Model.minBrightness(monitor), brightnessOf(monitor) + (dx > 0 ? 5 : -5)))
      } else if (row.type === "scale") {
        var scales = Model.scaleOptions(monitor)
        var next = Model.nearestIndex(scales, monitor.scale) + (dx > 0 ? 1 : -1)
        if (next >= 0 && next < scales.length) hostWidget.setScale(monitor.name, scales[next])
      }
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

  Timer {
    id: textSizeSettle
    interval: 1500
    onTriggered: root.textSizePending = -1
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(20)
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

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
              text: root.tr("displays")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              Layout.fillWidth: true
              Layout.rightMargin: root.inset
              horizontalAlignment: Text.AlignRight
              text: root.tr("displaysHint")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Item { width: 1; height: Style.space(8) }

          Column {
            id: displayList
            width: parent.width
            spacing: Style.space(16)

            // Indexed by position rather than by the monitor objects, so a
            // state refresh updates each card in place instead of rebuilding
            // it (which would cut a slider drag short).
            Repeater {
              model: root.displays.length

              Column {
                id: card
                required property int index
                readonly property var monitor: root.displays[index] || ({})
                readonly property bool mirrored: (monitor.mirrorOf || "none") !== "none"
                readonly property bool software: monitor.brightnessBackend === "software"
                readonly property var scales: Model.scaleOptions(monitor)
                readonly property int brightnessRow: root.rowIndex("brightness", monitor.name)
                readonly property int rotateRow: root.rowIndex("rotate", monitor.name)
                readonly property int scaleRow: root.rowIndex("scale", monitor.name)
                width: displayList.width
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  leftPadding: root.inset
                  rightPadding: root.inset
                  text: Model.displayName(root.lang, card.monitor) + "  ·  " + card.monitor.name
                    + (card.mirrored ? "  →  " + card.monitor.mirrorOf : "")
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    Layout.leftMargin: root.inset
                    Layout.fillWidth: true
                    text: root.tr("brightness") + (card.software && !card.mirrored ? "  ·  " + root.tr("softwareDim") : "")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.rightMargin: root.inset
                    visible: root.brightnessAdjustable(card.monitor)
                    text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessOf(card.monitor)) + "%"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                CursorSurface {
                  x: root.inset
                  width: parent.width - root.inset * 2
                  height: brightnessSlider.implicitHeight + Style.spacing.controlGap
                  visible: root.brightnessAdjustable(card.monitor)
                  hasCursor: root.cursorActive && root.cursorIndex === card.brightnessRow
                  foreground: root.foreground
                  outline: true

                  PanelSlider {
                    id: brightnessSlider
                    bar: root.bar
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(6)
                    minimum: Model.minBrightness(card.monitor)
                    maximum: 100
                    step: 1
                    integer: true
                    value: root.brightnessOf(card.monitor)
                    onMoved: function(v) { if (root.hostWidget) root.hostWidget.setBrightness(card.monitor.name, v) }
                    onReleased: function(v) { if (root.hostWidget) root.hostWidget.setBrightness(card.monitor.name, v) }
                  }

                  HoverHandler {
                    onHoveredChanged: if (hovered) { root.cursorActive = true; root.cursorIndex = card.brightnessRow }
                  }
                }

                Text {
                  width: parent.width
                  leftPadding: root.inset
                  rightPadding: root.inset
                  visible: !root.brightnessAdjustable(card.monitor)
                  text: card.monitor.brightnessBackend === "unknown" ? root.tr("detecting") : root.tr("mirrorDim")
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                  elide: Text.ElideRight
                }

                Item { width: 1; height: Style.space(2) }

                RowLayout {
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  Text {
                    Layout.leftMargin: root.inset
                    Layout.preferredWidth: Style.space(64)
                    text: root.tr("rotation")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  ButtonGroup {
                    spacing: Style.space(4)
                    focusable: false
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    value: String((card.monitor.transform || 0) % 4)
                    options: Model.ROTATIONS.map(function(t) { return { value: String(t), label: Model.rotationLabel(t) } })
                    cursorIndex: root.cursorActive && root.cursorIndex === card.rotateRow ? (card.monitor.transform || 0) % 4 : -1
                    onHovered: function(index, isHovered) { if (isHovered) { root.cursorActive = true; root.cursorIndex = card.rotateRow } }
                    onChanged: function(value) { if (root.hostWidget) root.hostWidget.rotate(card.monitor.name, Number(value)) }
                  }

                  Item { Layout.fillWidth: true }
                }

                RowLayout {
                  width: parent.width
                  visible: !card.mirrored
                  spacing: Style.spacing.controlGap

                  Text {
                    Layout.leftMargin: root.inset
                    Layout.preferredWidth: Style.space(64)
                    text: root.tr("scale")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  ButtonGroup {
                    readonly property int current: Model.nearestIndex(card.scales, card.monitor.scale)
                    spacing: Style.space(4)
                    focusable: false
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    value: String(card.scales[current])
                    options: card.scales.map(function(sc) { return { value: String(sc), label: Model.scaleLabel(sc) } })
                    cursorIndex: root.cursorActive && root.cursorIndex === card.scaleRow ? current : -1
                    onHovered: function(index, isHovered) { if (isHovered) { root.cursorActive = true; root.cursorIndex = card.scaleRow } }
                    onChanged: function(value) { if (root.hostWidget) root.hostWidget.setScale(card.monitor.name, Number(value)) }
                  }

                  Item { Layout.fillWidth: true }
                }
              }
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
              Layout.fillWidth: true
              text: root.tr("textSize")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              Layout.rightMargin: root.inset
              text: Model.TEXT_SIZE_STOPS[textSizeSlider.dragging ? Math.round(textSizeSlider.liveValue) : root.textSizeIndex] + "px"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Item { width: 1; height: Style.space(6) }

          CursorSurface {
            x: root.inset
            width: parent.width - root.inset * 2
            height: textSizeSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.cursorIndex === root.rowIndex("textsize")
            foreground: root.foreground
            outline: true

            PanelSlider {
              id: textSizeSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: Model.TEXT_SIZE_STOPS.length - 1
              step: 1
              integer: true
              tickCount: Model.TEXT_SIZE_STOPS.length
              value: root.textSizeIndex
              onReleased: function(v) { root.setTextSizeIndex(Math.round(v)) }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) { root.cursorActive = true; root.cursorIndex = root.rowIndex("textsize") }
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
