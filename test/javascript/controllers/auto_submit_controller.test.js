import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import AutoSubmitController from "../../../app/javascript/controllers/auto_submit_controller.js"

const PAGE = `
  <form data-controller="auto-submit">
    <select name="month" data-action="change->auto-submit#choose keydown->auto-submit#keydown keyup->auto-submit#keyup blur->auto-submit#leave">
      <option value="1">January</option>
      <option value="2" selected>February</option>
      <option value="3">March</option>
    </select>
  </form>`

let page
let sent

beforeEach(async () => {
  page = await mount("auto-submit", AutoSubmitController, PAGE)
  sent = 0
  page.element.requestSubmit = () => sent++
})

afterEach(() => page.stop())

const select = () => page.element.querySelector("select")
const key = (type, key, options = {}) =>
  select().dispatchEvent(new KeyboardEvent(type, { key, bubbles: true, ...options }))

// An arrow key on a closed select: the key goes down, the select changes,
// the key comes up.
function step(arrow) {
  key("keydown", arrow)
  select().dispatchEvent(new Event("change", { bubbles: true }))
  key("keyup", arrow)
}

test("a choice made in the select's list is sent at once", () => {
  select().dispatchEvent(new Event("change", { bubbles: true }))

  assert.equal(sent, 1)
})

test("steps taken by arrow keys wait for Enter, and Enter sends them once", () => {
  step("ArrowDown")
  step("ArrowDown")
  assert.equal(sent, 0)

  key("keydown", "Enter")
  assert.equal(sent, 1)

  key("keydown", "Enter")
  assert.equal(sent, 1, "nothing is held any more")
})

test("steps taken by arrow keys are sent when the reader leaves the select", () => {
  step("ArrowUp")
  select().dispatchEvent(new Event("blur"))

  assert.equal(sent, 1)
})

test("leaving a select that hasn't changed sends nothing", () => {
  select().dispatchEvent(new Event("blur"))

  assert.equal(sent, 0)
})

test("Alt+ArrowDown opens the list rather than stepping, so the choice made there is sent at once", () => {
  key("keydown", "ArrowDown", { altKey: true })
  select().dispatchEvent(new Event("change", { bubbles: true }))

  assert.equal(sent, 1)
})
