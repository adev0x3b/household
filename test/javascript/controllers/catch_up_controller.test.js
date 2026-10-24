import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount, settle } from "../support/stimulus.js"

// The page's live streams are plain elements here, defined before Turbo
// loads so that it doesn't define its own, which would open a connection to
// the server. Hence the controller and Turbo are imported only after.
customElements.define("turbo-cable-stream-source", class extends HTMLElement {})
const { default: CatchUpController } = await import("../../../app/javascript/controllers/catch_up_controller.js")
const { Turbo } = await import("@hotwired/turbo-rails")

// The parts of the layout the controller looks at: a live stream, the toasts
// and the modal it keeps through a refresh, and a form the reader may change.
const LAYOUT = `
  <div data-controller="catch-up">
    <turbo-cable-stream-source connected></turbo-cable-stream-source>
    <div id="toast-container" data-catch-up-target="kept"></div>
    <div id="modals" data-catch-up-target="kept"></div>
    <main>
      <input id="title" value="Dune">
      <input id="read" type="checkbox">
      <details id="notes"><summary>Notes</summary></details>
    </main>
  </div>
`

let mounted, refreshes
const originalRefresh = Turbo.session.refresh

beforeEach(async () => {
  refreshes = []
  Turbo.session.refresh = (url) => refreshes.push(url)
  mounted = await mount("catch-up", CatchUpController, LAYOUT)
})

afterEach(() => {
  Turbo.session.refresh = originalRefresh
  mounted.stop()
})

const turbo = (name, detail = {}) => document.dispatchEvent(new CustomEvent(`turbo:${name}`, { detail }))

// Turbo's own stream element, which announces itself and then asks Turbo for
// what it carries. It takes itself off the page once it has.
async function push(action) {
  document.body.insertAdjacentHTML(
    "beforeend",
    `<turbo-stream action="${action}" target="modals"><template></template></turbo-stream>`
  )
  while (document.querySelector("turbo-stream")) await new Promise((resolve) => setTimeout(resolve, 5))
}

// Whether a morph would leave the element as it is.
function keptThroughMorph(element) {
  const event = new CustomEvent("turbo:before-morph-element", { bubbles: true, cancelable: true, detail: {} })
  element.dispatchEvent(event)
  return event.defaultPrevented
}

function keptAttribute(element, attributeName) {
  const event = new CustomEvent("turbo:before-morph-attribute", {
    bubbles: true,
    cancelable: true,
    detail: { attributeName }
  })
  element.dispatchEvent(event)
  return event.defaultPrevented
}

const toasts = () => document.getElementById("toast-container")
const stream = () => document.querySelector("turbo-cable-stream-source")

test("a page the browser shows again from its cache is refreshed", () => {
  window.dispatchEvent(new window.PageTransitionEvent("pageshow", { persisted: true }))

  assert.deepEqual(refreshes, ["https://household.test/"])
})

test("a page loaded afresh is not refreshed again", () => {
  window.dispatchEvent(new window.PageTransitionEvent("pageshow", { persisted: false }))

  assert.deepEqual(refreshes, [])
})

test("a live stream connected again after a drop refreshes the page", async () => {
  stream().removeAttribute("connected")
  await settle()
  assert.deepEqual(refreshes, [])

  stream().setAttribute("connected", "")
  await settle()
  assert.equal(refreshes.length, 1)
})

test("a live stream connecting for the first time refreshes nothing", async () => {
  document
    .querySelector("main")
    .insertAdjacentHTML("beforeend", "<turbo-cable-stream-source></turbo-cable-stream-source>")
  const added = document.querySelectorAll("turbo-cable-stream-source")[1]

  added.setAttribute("connected", "")
  await settle()

  assert.deepEqual(refreshes, [])
})

test("the refresh that follows a pushed refresh keeps the toasts and the modal", async () => {
  await push("refresh")
  turbo("visit")

  assert.equal(keptThroughMorph(toasts()), true)
  assert.equal(keptThroughMorph(document.getElementById("modals")), true)
  assert.equal(keptThroughMorph(document.querySelector("main")), false)
})

test("a stream that isn't a refresh keeps nothing", async () => {
  await push("update")
  turbo("visit")

  assert.equal(keptThroughMorph(toasts()), false)
})

test("the refresh the controller asks for keeps the toasts too", () => {
  window.dispatchEvent(new window.PageTransitionEvent("pageshow", { persisted: true }))
  turbo("visit")

  assert.equal(keptThroughMorph(toasts()), true)
})

test("a page brought by the reader's own press keeps nothing, though a refresh was pushed before it", async () => {
  await push("refresh")
  turbo("submit-end")
  turbo("visit")

  assert.equal(keptThroughMorph(toasts()), false)
})

test("a refresh pushed and never carried out is forgotten at the reader's next click", async () => {
  await push("refresh")
  turbo("click")
  turbo("visit")

  assert.equal(keptThroughMorph(toasts()), false)
})

test("once the refreshed page has loaded, a later morph keeps nothing", async () => {
  await push("refresh")
  turbo("visit")
  turbo("load")

  assert.equal(keptThroughMorph(toasts()), false)
})

test("a refresh keeps what the reader typed, ticked or opened", async () => {
  document.getElementById("title").value = "Dune Messiah"
  document.getElementById("read").checked = true
  await push("refresh")
  turbo("visit")

  assert.equal(keptAttribute(document.getElementById("title"), "value"), true)
  assert.equal(keptAttribute(document.getElementById("read"), "checked"), true)
  assert.equal(keptAttribute(document.getElementById("notes"), "open"), true)
})

test("a refresh brings the saved value to a field the reader left alone", async () => {
  await push("refresh")
  turbo("visit")

  assert.equal(keptAttribute(document.getElementById("title"), "value"), false)
  assert.equal(keptAttribute(document.getElementById("read"), "checked"), false)
})

test("a page that isn't a refresh takes the fields as the server sends them", async () => {
  document.getElementById("title").value = "Dune Messiah"
  turbo("visit")

  assert.equal(keptAttribute(document.getElementById("title"), "value"), false)
})
