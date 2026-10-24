import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount, settle } from "../support/stimulus.js"
import NestedFieldsController from "../../../app/javascript/controllers/nested_fields_controller.js"

// A recipe's steps as Components::NestedFields draws them: a saved step
// names its id and carries a destroy flag, a list saved whole has neither.
function step(index, { id = null, instruction = "", savedWhole = false } = {}) {
  const prefix = `recipe[recipe_steps_attributes][${index}]`
  const identity = savedWhole
    ? ""
    : `${id ? `<input type="hidden" name="${prefix}[id]" value="${id}">` : ""}
       <input type="hidden" name="${prefix}[_destroy]" value="false" data-nested-fields-target="destroyField">`
  return `
    <div data-nested-fields-target="row">
      ${identity}
      <textarea name="${prefix}[instruction]">${instruction}</textarea>
      <button type="button" data-action="click->nested-fields#remove"><i class="fa-xmark"></i></button>
    </div>
  `
}

function list(rows, { savedWhole = false } = {}) {
  return `
    <form data-controller="nested-fields">
      <div data-nested-fields-target="container">${rows.join("")}</div>
      <template data-nested-fields-target="template">${step("NEW_RECORD", { savedWhole })}</template>
      <button type="button" class="add" data-action="click->nested-fields#add">Add</button>
    </form>
  `
}

let page
afterEach(() => page.stop())

const rows = () => Array.from(document.querySelectorAll('[data-nested-fields-target="row"]'))
const shown = () => rows().filter((row) => !row.hidden)
const sent = () => Array.from(new window.FormData(document.querySelector("form")).keys())
const add = () => document.querySelector(".add").click()
const removeButton = (row) => row.querySelector("button")

test("each row added is named under its own index, never one a saved row has", async () => {
  page = await mount("nested-fields", NestedFieldsController, list([step(7, { id: 7, instruction: "Boil" })]))

  add()
  add()

  assert.deepEqual(
    rows().map((row) => row.querySelector("textarea").name),
    [
      "recipe[recipe_steps_attributes][7][instruction]",
      "recipe[recipe_steps_attributes][-1][instruction]",
      "recipe[recipe_steps_attributes][-2][instruction]"
    ]
  )
})

test("a saved row removed is hidden and still sent, marked for the server to delete", async () => {
  page = await mount("nested-fields", NestedFieldsController, list([step(7, { id: 7, instruction: "Boil" })]))

  removeButton(rows()[0]).click()

  assert.equal(rows().length, 1)
  assert.equal(rows()[0].hidden, true)
  assert.equal(document.querySelector('[name="recipe[recipe_steps_attributes][7][_destroy]"]').value, "1")
  assert.ok(sent().includes("recipe[recipe_steps_attributes][7][id]"))
})

test("a row added and then removed is hidden and marked, so the server drops it", async () => {
  page = await mount("nested-fields", NestedFieldsController, list([]))

  add()
  await settle()
  removeButton(rows()[0]).click()

  assert.equal(shown().length, 0)
  assert.equal(document.querySelector('[name="recipe[recipe_steps_attributes][-1][_destroy]"]').value, "1")
  assert.ok(!sent().includes("recipe[recipe_steps_attributes][-1][id]"))
})

test("only the row whose button was pressed goes, from its icon too", async () => {
  page = await mount(
    "nested-fields",
    NestedFieldsController,
    list([step(7, { id: 7, instruction: "Boil" }), step(8, { id: 8, instruction: "Drain" })])
  )

  rows()[1].querySelector("i").click()

  assert.deepEqual(
    shown().map((row) => row.querySelector("textarea").value),
    ["Boil"]
  )
  assert.equal(document.querySelector('[name="recipe[recipe_steps_attributes][7][_destroy]"]').value, "false")
})

test("a row of a list saved whole is taken out, so the list is sent without it", async () => {
  page = await mount(
    "nested-fields",
    NestedFieldsController,
    list([step(0, { savedWhole: true, instruction: "Boil" }), step(1, { savedWhole: true, instruction: "Drain" })], {
      savedWhole: true
    })
  )

  removeButton(rows()[0]).click()

  assert.deepEqual(sent(), ["recipe[recipe_steps_attributes][1][instruction]"])
})
