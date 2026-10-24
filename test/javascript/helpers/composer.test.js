import { test } from "node:test"
import assert from "node:assert/strict"
import { Composer } from "../../../app/javascript/helpers/composer.js"

function composer({ touch = false, scrollHeight = 40 } = {}) {
  const form = {
    submitted: 0,
    requestSubmit() {
      this.submitted += 1
    }
  }
  const input = { value: "Hello", style: {}, scrollHeight }
  return { form, input, composer: new Composer(form, input, { touch }) }
}

function enter(options = {}) {
  return {
    key: "Enter",
    shiftKey: false,
    isComposing: false,
    prevented: false,
    preventDefault() {
      this.prevented = true
    },
    ...options
  }
}

test("Enter sends", () => {
  const { form, composer: box } = composer()
  const event = enter()

  box.keydown(event)
  assert.equal(form.submitted, 1)
  assert.equal(event.prevented, true)
})

test("Shift+Enter adds a line", () => {
  const { form, composer: box } = composer()
  const event = enter({ shiftKey: true })

  box.keydown(event)
  assert.equal(form.submitted, 0)
  assert.equal(event.prevented, false)
})

test("Enter while composing with an input method adds nothing and sends nothing", () => {
  const { form, composer: box } = composer()

  box.keydown(enter({ isComposing: true }))
  assert.equal(form.submitted, 0)
})

test("on a touch device Enter adds a line", () => {
  const { form, composer: box } = composer({ touch: true })

  box.keydown(enter())
  assert.equal(form.submitted, 0)
})

test("another key is left alone", () => {
  const { form, composer: box } = composer()
  const event = enter({ key: "a" })

  box.keydown(event)
  assert.equal(form.submitted, 0)
  assert.equal(event.prevented, false)
})

test("the box grows with its text", () => {
  const { input, composer: box } = composer({ scrollHeight: 72 })

  box.grow()
  assert.equal(input.style.height, "72px")
})

test("the box stops growing at its greatest height", () => {
  const { input, composer: box } = composer({ scrollHeight: 900 })

  box.grow()
  assert.equal(input.style.height, "160px")
})

test("clearing empties the box and shrinks it", () => {
  const { input, composer: box } = composer({ scrollHeight: 24 })

  box.clear()
  assert.equal(input.value, "")
  assert.equal(input.style.height, "24px")
})
