const assert = require("assert")
const Model = require("../Model.js")

const cases = {
  "parses helper state": () => {
    const s = Model.parseState('{"mode":"duplicate","position":"left","hasExternal":true,"monitors":[{"name":"eDP-1"},{"bad":1}]}')
    assert.strictEqual(s.mode, "duplicate")
    assert.strictEqual(s.position, "left")
    assert.strictEqual(s.hasExternal, true)
    assert.strictEqual(s.monitors.length, 1)
  },
  "falls back on garbage": () => {
    assert.deepStrictEqual(Model.parseState("not json"), Model.emptyState())
    assert.strictEqual(Model.parseState('{"position":"sideways"}').position, "right")
  },
  "picks the language": () => {
    assert.strictEqual(Model.language("auto", "es_CO"), "es")
    assert.strictEqual(Model.language("auto", "en_US"), "en")
    assert.strictEqual(Model.language("es", "en_US"), "es")
    assert.strictEqual(Model.tr("es", "duplicate"), "Duplicar")
    assert.strictEqual(Model.tr("fr", "duplicate"), "Duplicate")
  },
  "every string exists in both languages": () => {
    assert.deepStrictEqual(Object.keys(Model.STRINGS.es).sort(), Object.keys(Model.STRINGS.en).sort())
    for (const mode of Model.MODES) {
      assert.ok(Model.STRINGS.en[mode] && Model.STRINGS.en[mode + "Hint"], mode)
    }
  },
  "rotation labels and cycling": () => {
    assert.strictEqual(Model.rotationLabel(2), "180°")
    assert.strictEqual(Model.rotationLabel(5), "90°")
    assert.strictEqual(Model.nextIndex([0, 1, 2, 3], 3, 1), 0)
    assert.strictEqual(Model.nextIndex([0, 1, 2, 3], 0, -1), 3)
  },
  "glyphs are single code points": () => {
    assert.strictEqual(Model.glyph(0xF0379).codePointAt(0), 0xF0379)
  },
  "software brightness levels": () => {
    assert.deepStrictEqual(Model.parseLevels('{"HDMI-A-1":70,"DP-1":100,"x":"y","DP-2":2}'), { "HDMI-A-1": 70, "DP-2": 10 })
    assert.deepStrictEqual(Model.parseLevels("[1,2]"), {})
    assert.deepStrictEqual(Model.parseLevels("garbage"), {})
    assert.ok(Math.abs(Model.dimOpacity(70) - 0.3) < 1e-9)
    assert.ok(Math.abs(Model.dimOpacity(0) - 0.9) < 1e-9)
    assert.strictEqual(Model.minBrightness({ brightnessBackend: "software" }), 10)
    assert.strictEqual(Model.minBrightness({ brightnessBackend: "hardware" }), 1)
  },
  "scales are clean for the mode": () => {
    assert.strictEqual(Model.cleanScale(1.6, 1920, 1080), 1.6)
    assert.strictEqual(Model.cleanScale(1.25, 1920, 1080), 1.25)
    assert.strictEqual(Model.cleanScale(1.6, 2560, 1600), 1.6)
    assert.deepStrictEqual(Model.scaleOptions({ width: 1920, height: 1080, transform: 0 }), [1, 1.25, 1.6, 2])
    assert.deepStrictEqual(Model.scaleOptions({ width: 3840, height: 2160, transform: 0 }), [1, 1.25, 1.6, 2, 3, 4])
    assert.strictEqual(Model.scaleLabel(1.25), "1.25x")
    assert.strictEqual(Model.nearestIndex([1, 1.25, 1.6, 2], 1.5), 2)
  },
  "laptop gets a friendly name": () => {
    assert.strictEqual(Model.displayName("es", { internal: true, name: "eDP-1" }), "Pantalla del portátil")
    assert.strictEqual(Model.displayName("en", { internal: false, label: "GWD ARZOPA", name: "HDMI-A-1" }), "GWD ARZOPA")
  }
}

let failed = 0
for (const [name, fn] of Object.entries(cases)) {
  try {
    fn()
    console.log("ok   " + name)
  } catch (e) {
    failed++
    console.log("FAIL " + name + ": " + e.message)
  }
}
process.exit(failed ? 1 : 0)
