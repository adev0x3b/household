import { test } from "node:test"
import assert from "node:assert/strict"
import { confirmationFor } from "../../../app/javascript/helpers/confirmation.js"

// Just enough of an element for the helper: its attributes and its words.
function element(attributes = {}, text = "") {
  return { getAttribute: (name) => attributes[name] ?? null, textContent: text }
}

function form({ method = null, hiddenMethod = null } = {}) {
  const field = hiddenMethod ? { value: hiddenMethod } : null
  return { ...element({ method }), querySelector: () => field }
}

test("names the button after the button that submits", () => {
  const submitter = element({ "aria-label": "Delete book" })

  assert.equal(confirmationFor("Delete Dune?", { form: form(), submitter }).confirm, "Delete book")
})

test("names it after a menu entry's words when it has no label", () => {
  const press = element({ "data-turbo-confirm": "Delete Dune?" }, "\n  Delete\n")

  assert.equal(confirmationFor("Delete Dune?", { form: form(), press }).confirm, "Delete")
})

test("leaves the default words to a press that asked another question", () => {
  const press = element({ "data-turbo-confirm": "Delete Neuromancer?", "aria-label": "Delete" })

  assert.equal(confirmationFor("Delete Dune?", { form: form(), press }).confirm, undefined)
})

test("leaves the default words when nothing was pressed", () => {
  assert.equal(confirmationFor("Stop the uploads?", { form: form() }).confirm, undefined)
})

test("sets a deletion apart, whether button_to or Turbo carries the method", () => {
  assert.equal(confirmationFor("?", { form: form({ hiddenMethod: "delete" }) }).danger, true)
  assert.equal(confirmationFor("?", { form: form({ method: "DELETE" }) }).danger, true)
  assert.equal(confirmationFor("?", { form: form({ method: "patch" }) }).danger, false)
  assert.equal(confirmationFor("?", { form: form({ method: "post" }) }).danger, false)
})
