import { test } from "node:test"
import assert from "node:assert/strict"
import { Speedometer } from "../../../app/javascript/uploader/speedometer.js"

function speedometer() {
  const clock = { at: 0 }
  return { clock, speedometer: new Speedometer(() => clock.at) }
}

test("says nothing before a second has been measured", () => {
  const { clock, speedometer: meter } = speedometer()

  meter.record(0)
  clock.at = 900
  meter.record(9000)
  assert.equal(meter.bytesPerSecond, null)
})

test("measures bytes a second over its samples", () => {
  const { clock, speedometer: meter } = speedometer()

  meter.record(0)
  clock.at = 2000
  meter.record(4000)
  assert.equal(meter.bytesPerSecond, 2000)
})

test("forgets samples older than its window", () => {
  const { clock, speedometer: meter } = speedometer()

  meter.record(0)
  clock.at = 1000
  meter.record(100)
  clock.at = 10000
  meter.record(9100)
  clock.at = 11000
  meter.record(10100)
  assert.equal(meter.bytesPerSecond, 1000)
})

test("says nothing when nothing moved", () => {
  const { clock, speedometer: meter } = speedometer()

  meter.record(500)
  clock.at = 3000
  meter.record(500)
  assert.equal(meter.bytesPerSecond, null)
})

test("starts over when reset", () => {
  const { clock, speedometer: meter } = speedometer()

  meter.record(0)
  clock.at = 2000
  meter.record(4000)
  meter.reset()
  assert.equal(meter.bytesPerSecond, null)
})
