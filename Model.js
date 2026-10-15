// Pure helpers shared by BarWidget.qml and Panel.qml. No QML imports, so the
// test runner can load this file under node as well.

var MODES = ["pc", "duplicate", "extend", "second"]
var POSITIONS = ["left", "right", "above", "below"]
var ROTATIONS = [0, 1, 2, 3]

var STRINGS = {
  en: {
    title: "Display Switch",
    project: "Project",
    pc: "PC screen only",
    duplicate: "Duplicate",
    extend: "Extend",
    second: "Second screen only",
    pcHint: "Only the main screen stays on",
    duplicateHint: "Same image on every screen",
    extendHint: "One desktop across the screens",
    secondHint: "Main screen off, external only",
    single: "Single display",
    applying: "Applying…",
    current: "Current",
    extendTo: "External display position",
    left: "Left",
    right: "Right",
    above: "Above",
    below: "Below",
    rotation: "Rotation",
    rotationHint: "Remembered per device",
    laptop: "Laptop screen",
    off: "off",
    footer: "↑↓ Select · ←→ Change · Enter Apply · 1-4 Mode",
    tooltip: "Display: ",
    tooltipCycle: "Right-click: next mode"
  },
  es: {
    title: "Proyectar",
    project: "Modo",
    pc: "Solo pantalla del PC",
    duplicate: "Duplicar",
    extend: "Extender",
    second: "Solo segunda pantalla",
    pcHint: "Solo queda encendida la pantalla principal",
    duplicateHint: "La misma imagen en todas las pantallas",
    extendHint: "Un escritorio repartido entre pantallas",
    secondHint: "Apaga la principal y usa solo la externa",
    single: "Una sola pantalla",
    applying: "Aplicando…",
    current: "Actual",
    extendTo: "Posición de la pantalla externa",
    left: "Izquierda",
    right: "Derecha",
    above: "Arriba",
    below: "Abajo",
    rotation: "Giro",
    rotationHint: "Se recuerda por dispositivo",
    laptop: "Pantalla del portátil",
    off: "apagada",
    footer: "↑↓ Elegir · ←→ Cambiar · Enter Aplicar · 1-4 Modo",
    tooltip: "Pantalla: ",
    tooltipCycle: "Clic derecho: siguiente modo"
  }
}

function language(setting, localeName) {
  if (setting === "es" || setting === "en") return setting
  return String(localeName || "").indexOf("es") === 0 ? "es" : "en"
}

function tr(lang, key) {
  var table = STRINGS[lang] || STRINGS.en
  return table[key] !== undefined ? table[key] : (STRINGS.en[key] || key)
}

// Nerd Font glyphs live above the BMP; build them from code points instead of
// pasting characters an editor might mangle.
function glyph(codePoint) {
  var c = codePoint - 0x10000
  return String.fromCharCode(0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF))
}

function modeIcon(mode) {
  if (mode === "pc") return glyph(0xF0322)        // nf-md-laptop
  if (mode === "duplicate") return glyph(0xF018F) // nf-md-content_copy
  if (mode === "second") return glyph(0xF0379)    // nf-md-monitor
  if (mode === "extend") return glyph(0xF037A)    // nf-md-monitor_multiple
  return glyph(0xF0379)
}

function modeLabel(lang, mode) {
  if (MODES.indexOf(mode) < 0) return tr(lang, "single")
  return tr(lang, mode)
}

function rotationLabel(transform) {
  return String((Number(transform) % 4) * 90) + "°"
}

function nextIndex(list, value, delta) {
  var i = list.indexOf(value)
  if (i < 0) i = 0
  return (i + delta + list.length) % list.length
}

function emptyState() {
  return {
    mode: "single",
    storedMode: "extend",
    position: "right",
    hasExternal: false,
    primary: "",
    monitors: []
  }
}

function parseState(raw) {
  var parsed = null
  try {
    parsed = raw ? JSON.parse(String(raw)) : null
  } catch (e) {
    parsed = null
  }
  if (!parsed || typeof parsed !== "object") return emptyState()

  var state = emptyState()
  if (typeof parsed.mode === "string") state.mode = parsed.mode
  if (typeof parsed.storedMode === "string") state.storedMode = parsed.storedMode
  if (POSITIONS.indexOf(parsed.position) >= 0) state.position = parsed.position
  state.hasExternal = parsed.hasExternal === true
  if (typeof parsed.primary === "string") state.primary = parsed.primary
  if (Array.isArray(parsed.monitors)) {
    state.monitors = parsed.monitors.filter(function(m) {
      return m && typeof m.name === "string" && m.name !== ""
    })
  }
  return state
}

function displayName(lang, monitor) {
  if (!monitor) return ""
  if (monitor.internal) return tr(lang, "laptop")
  return String(monitor.label || monitor.name)
}

if (typeof module !== "undefined") {
  module.exports = {
    MODES: MODES,
    POSITIONS: POSITIONS,
    ROTATIONS: ROTATIONS,
    STRINGS: STRINGS,
    language: language,
    tr: tr,
    glyph: glyph,
    modeIcon: modeIcon,
    modeLabel: modeLabel,
    rotationLabel: rotationLabel,
    nextIndex: nextIndex,
    emptyState: emptyState,
    parseState: parseState,
    displayName: displayName
  }
}
