import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import TypedFieldsController from "../../../app/javascript/controllers/typed_fields_controller.js"

// A recipe's form as Components::Form draws it, with whatever names it
// carries from before it was shown again.
function form({ typedBefore = [] } = {}) {
  return `
    <form data-controller="typed-fields" data-action="submit->typed-fields#note">
      <input type="hidden" name="recipe[lock_version]" value="3">
      ${typedBefore.map((name) => `<input type="hidden" name="typed_fields[]" value="${name}">`).join("")}
      <input name="recipe[name]" value="Roast chicken">
      <textarea name="recipe[description]">Sunday's</textarea>
      <input type="hidden" name="recipe[favorite]" value="0">
      <input type="checkbox" name="recipe[favorite]" value="1">
      <select name="recipe[course]"><option value="main" selected>Main</option><option value="side">Side</option></select>
      <div class="steps">
        <textarea name="recipe[recipe_steps_attributes][0][instruction]">Roast it</textarea>
      </div>
    </form>
  `
}

let page
afterEach(() => page.stop())

const field = (name) => document.querySelector(`[name="${name}"]`)
const sentNames = () =>
  Array.from(document.querySelectorAll('input[name="typed_fields[]"]')).map((input) => input.value)
const typed = () => sentNames().filter((name) => name !== "")

function send({ prevented = false } = {}) {
  const event = new Event("submit", { bubbles: true, cancelable: true })
  if (prevented) event.preventDefault()
  document.querySelector("form").dispatchEvent(event)
}

test("a form sent untouched names no field, and still says so", async () => {
  page = await mount("typed-fields", TypedFieldsController, form())

  send()

  assert.deepEqual(sentNames(), [""])
})

test("the fields changed since the form was drawn are named, whatever kind of control", async () => {
  page = await mount("typed-fields", TypedFieldsController, form())

  field("recipe[description]").value = "For guests"
  document.querySelector('[type="checkbox"]').checked = true
  field("recipe[course]").value = "side"
  send()

  assert.deepEqual(typed().sort(), ["recipe[course]", "recipe[description]", "recipe[favorite]"])
})

test("a field changed and changed back counts as left alone", async () => {
  page = await mount("typed-fields", TypedFieldsController, form())

  field("recipe[name]").value = "Roast duck"
  field("recipe[name]").value = "Roast chicken"
  send()

  assert.deepEqual(typed(), [])
})

test("a row added to a list, or taken off it, is named", async () => {
  page = await mount("typed-fields", TypedFieldsController, form())

  document
    .querySelector(".steps")
    .insertAdjacentHTML(
      "beforeend",
      '<textarea name="recipe[recipe_steps_attributes][1][instruction]">Rest it</textarea>'
    )
  field("recipe[recipe_steps_attributes][0][instruction]").remove()
  send()

  assert.deepEqual(typed().sort(), [
    "recipe[recipe_steps_attributes][0][instruction]",
    "recipe[recipe_steps_attributes][1][instruction]"
  ])
})

test("a form shown again still names what was typed before, once each, however often it is sent", async () => {
  page = await mount("typed-fields", TypedFieldsController, form({ typedBefore: ["recipe[name]"] }))

  field("recipe[description]").value = "For guests"
  send()
  send()

  assert.deepEqual(typed().sort(), ["recipe[description]", "recipe[name]"])
})

test("a send another controller stopped names nothing", async () => {
  page = await mount("typed-fields", TypedFieldsController, form())

  field("recipe[name]").value = "Roast duck"
  send({ prevented: true })

  assert.deepEqual(typed(), [])
})
