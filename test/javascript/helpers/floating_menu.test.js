import { test } from "node:test"
import assert from "node:assert/strict"
import { placement } from "../../../app/javascript/helpers/floating_menu.js"

const viewport = { width: 390, height: 844 }
const menu = { width: 176, height: 58 }
// A card's "more", near the right edge of a phone's screen.
const button = { top: 100, bottom: 120, left: 330, right: 350 }

test("below its button, a small gap away, its right edge on the button's", () => {
  assert.deepEqual(placement(button, menu, viewport, { side: "below", align: "end" }), { top: 124, left: 174 })
})

test("above its button, its bottom edge the same gap away", () => {
  assert.deepEqual(placement(button, menu, viewport, { side: "above", align: "end" }), { top: 38, left: 174 })
})

test("lined up with the button's left edge when asked to start there", () => {
  const smile = { top: 400, bottom: 436, left: 24, right: 60 }

  assert.equal(placement(smile, menu, viewport, { side: "above", align: "start" }).left, 24)
})

test("never past the window's left or right edge", () => {
  const nearLeft = { top: 100, bottom: 120, left: 4, right: 24 }
  const nearRight = { top: 100, bottom: 120, left: 370, right: 390 }

  assert.equal(placement(nearLeft, menu, viewport, { side: "below", align: "end" }).left, 8)
  assert.equal(placement(nearRight, menu, viewport, { side: "below", align: "start" }).left, 390 - 176 - 8)
})

test("a menu wider than the window starts at its left margin", () => {
  assert.equal(placement(button, { width: 400, height: 58 }, viewport, { side: "below", align: "end" }).left, 8)
})
