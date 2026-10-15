// Pure helpers shared by BarWidget.qml and Panel.qml. No QML imports, so the
// test runner can load this file under node as well.

var MODES = ["pc", "duplicate", "extend", "second"]
var POSITIONS = ["left", "right", "above", "below"]
var ROTATIONS = [0, 1, 2, 3]
// Same presets as Omarchy's display panel; each is rounded to a scale the
// display's mode divides into cleanly.
var SCALE_PRESETS = [1, 1.25, 1.6, 2, 3, 4]
var TEXT_SIZE_STOPS = [9, 10, 11, 12, 14, 16, 20]
var SOFTWARE_MIN_BRIGHTNESS = 10

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
    displays: "Displays",
    displaysHint: "Remembered per device",
    brightness: "Brightness",
    softwareDim: "dimmed in software",
    detecting: "Checking brightness control…",
    mirrorDim: "Follows the duplicated screen",
    rotation: "Rotation",
    scale: "Scale",
    textSize: "Text size",
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
    displays: "Pantallas",
    displaysHint: "Se recuerda por dispositivo",
    brightness: "Brillo",
    softwareDim: "atenuado por software",
    detecting: "Comprobando el control de brillo…",
    mirrorDim: "Sigue a la pantalla duplicada",
    rotation: "Giro",
    scale: "Escala",
    textSize: "Tamaño del texto",
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

function clamp(value, low, high) {
  var n = Number(value)
  if (!isFinite(n)) n = high
  return Math.max(low, Math.min(high, Math.round(n)))
}

function minBrightness(monitor) {
  return monitor && monitor.brightnessBackend === "software" ? SOFTWARE_MIN_BRIGHTNESS : 1
}

// Opacity of the black layer that dims a display to `level` percent.
function dimOpacity(level) {
  return 1 - clamp(level, SOFTWARE_MIN_BRIGHTNESS, 100) / 100
}

// software-brightness.json: { "<output>": <level> }. Anything unexpected is
// dropped, so a broken file leaves every display at full brightness.
function parseLevels(raw) {
  var parsed = null
  try {
    parsed = raw ? JSON.parse(String(raw)) : null
  } catch (e) {
    parsed = null
  }
  var levels = {}
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return levels
  for (var name in parsed) {
    var n = Number(parsed[name])
    if (isFinite(n) && n < 100) levels[name] = clamp(n, SOFTWARE_MIN_BRIGHTNESS, 100)
  }
  return levels
}

function gcd(a, b) {
  while (b) {
    var r = a % b
    a = b
    b = r
  }
  return a
}

// Hyprland only accepts scales where the mode divides into whole logical
// pixels (in 1/120 steps); round up to the nearest such value, as
// omarchy-hyprland-monitor-scaling does.
function cleanScale(scale, width, height) {
  var w = Math.round(Number(width) * 120)
  var h = Math.round(Number(height) * 120)
  var k = Math.round(Number(scale) * 120)
  if (!(w > 0 && h > 0 && k > 0)) return Number(scale) || 1
  var g = gcd(w, h)
  if (k > g) k = g
  while (g % k !== 0) k++
  return Math.round(k / 120 * 1000) / 1000
}

// Clean scales for a display, without duplicates, skipping any that would
// leave less than 960 logical pixels across.
function scaleOptions(monitor) {
  var w = monitor ? Number(monitor.width) : 0
  var h = monitor ? Number(monitor.height) : 0
  var rotated = monitor && (Number(monitor.transform) % 2) === 1
  var across = rotated ? h : w
  var seen = {}
  var list = []
  for (var i = 0; i < SCALE_PRESETS.length; i++) {
    var s = cleanScale(SCALE_PRESETS[i], w, h)
    if (seen[s]) continue
    if (across > 0 && i > 0 && across / s < 960) continue
    seen[s] = true
    list.push(s)
  }
  return list
}

function scaleLabel(scale) {
  return String(Math.round(Number(scale) * 100) / 100) + "x"
}

function nearestIndex(list, value) {
  var best = 0
  for (var i = 1; i < list.length; i++) {
    if (Math.abs(list[i] - value) < Math.abs(list[best] - value)) best = i
  }
  return best
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
    SCALE_PRESETS: SCALE_PRESETS,
    TEXT_SIZE_STOPS: TEXT_SIZE_STOPS,
    SOFTWARE_MIN_BRIGHTNESS: SOFTWARE_MIN_BRIGHTNESS,
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
    displayName: displayName,
    clamp: clamp,
    minBrightness: minBrightness,
    dimOpacity: dimOpacity,
    parseLevels: parseLevels,
    cleanScale: cleanScale,
    scaleOptions: scaleOptions,
    scaleLabel: scaleLabel,
    nearestIndex: nearestIndex
  }
}
