import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import "../support/dom.js"
import { FocusKeeper, replacementFor } from "../../../app/javascript/helpers/focus_keeper.js"

// A page as the layout draws it: the content, holding a day card and a list
// of rows to settle, and a modal's frame beside it.
const PAGE = `
  <main id="content" tabindex="-1">
    <div id="day_2026-10-21"><a id="day-1-2026-10-21-toggle" href="#">Done</a><a href="#">Title</a></div>
    <h2 id="heading" tabindex="-1">Needs attention</h2>
    <ul>
      <li><button id="first" data-focus-fallback="second heading">Skip</button></li>
      <li><button id="second" data-focus-fallback="first heading">Skip</button></li>
    </ul>
  </main>
  <div id="modals"><button id="save">Save</button></div>
`

let keeper

beforeEach(() => {
  document.body.innerHTML = PAGE
  keeper = new FocusKeeper(document.body, { content: () => document.getElementById("content") })
  keeper.start()
})

afterEach(() => {
  keeper.stop()
  document.body.replaceChildren()
})

// The observer is told once the code changing the page has finished.
const settle = () => new Promise((resolve) => setTimeout(resolve, 0))
const focused = () => document.activeElement.id || document.activeElement.tagName

test("a redrawn element gets the focus back by its id", async () => {
  document.getElementById("day-1-2026-10-21-toggle").focus()

  document.getElementById("day_2026-10-21").outerHTML =
    `<div id="day_2026-10-21"><a id="day-1-2026-10-21-toggle" href="#">Not done</a></div>`
  await settle()

  assert.equal(focused(), "day-1-2026-10-21-toggle")
  assert.equal(document.activeElement.textContent, "Not done")
})

test("a row that leaves the list hands the focus to its first fallback still there", async () => {
  document.getElementById("first").focus()

  document.getElementById("first").closest("li").remove()
  await settle()

  assert.equal(focused(), "second")
})

test("past every fallback, a focus in the content goes to the content", async () => {
  const card = document.getElementById("day_2026-10-21")
  card.querySelector("a:not([id])").focus()

  card.remove()
  await settle()

  assert.equal(focused(), "content")
})

test("a focus outside the content with nowhere to go is left alone", async () => {
  document.getElementById("save").focus()

  document.getElementById("modals").replaceChildren()
  await settle()

  assert.equal(document.activeElement, document.body)
})

test("a focus the reader moved elsewhere meanwhile stays where they put it", async () => {
  document.getElementById("first").focus()
  const second = document.getElementById("second")

  document.getElementById("first").closest("li").remove()
  document.getElementById("heading").focus()
  await settle()

  assert.equal(focused(), "heading")
  assert.ok(second.isConnected)
})

test("a change elsewhere on the page leaves the focus where it is", async () => {
  document.getElementById("second").focus()

  document.getElementById("modals").replaceChildren()
  await settle()

  assert.equal(focused(), "second")
})

test("a replacement that is hidden is passed over", () => {
  const gone = document.createElement("button")
  gone.id = "first"
  gone.dataset.focusFallback = "second heading"
  document.getElementById("first").hidden = true
  document.getElementById("second").closest("ul").setAttribute("inert", "")

  assert.equal(replacementFor(gone, document).id, "heading")
})

// Turbo switches the pressed button off while its form is sent, and the
// browser drops the focus of a button switched off.
function send(button, { answer = () => {} } = {}) {
  button.disabled = true
  button.blur()
  answer()
  button.disabled = false
  button.dispatchEvent(
    new CustomEvent("turbo:submit-end", { bubbles: true, detail: { formSubmission: { submitter: button } } })
  )
}

test("a button switched off while its form was sent takes the focus back once the answer is in", () => {
  const save = document.getElementById("save")
  save.focus()

  send(save)

  assert.equal(focused(), "save")
})

test("a focus moved elsewhere while the form was sent stays there", () => {
  const save = document.getElementById("save")
  save.focus()

  send(save, { answer: () => document.getElementById("heading").focus() })

  assert.equal(focused(), "heading")
})

test("once stopped, nothing is put back", async () => {
  document.getElementById("first").focus()
  keeper.stop()

  document.getElementById("first").closest("li").remove()
  await settle()

  assert.equal(document.activeElement, document.body)
})
