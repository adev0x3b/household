import { test, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount, settle } from "../support/stimulus.js"
import ModalController from "../../../app/javascript/controllers/modal_controller.js"

// jsdom has no modal dialogs and lays nothing out. The dialog opens and
// closes as the browser's does, as far as the controller can tell, and an
// element is seen unless it is hidden.
const { HTMLDialogElement } = window
HTMLDialogElement.prototype.showModal = function () {
  this.open = true
}
HTMLDialogElement.prototype.close = function () {
  this.open = false
  this.dispatchEvent(new Event("close"))
}
HTMLElement.prototype.getClientRects = function () {
  return this.closest("[hidden]") ? [] : [{}]
}

// The parts of the layout a modal meets: the page's toasts, with a failed
// request's toast kept as a template, the modals frame, and what opens one.
const PAGE = `
  <div id="toast-container">
    <template><div class="toast toast--alert">Offline</div></template>
  </div>
  <button id="opener">Edit</button>
  <div hidden><a id="folded-entry" href="#">Edit</a></div>
  <div id="modals"></div>
`

// A modal as Components::Modal draws it.
const modal = ({ title = "Edit book", fields = `<input id="title" name="title">` } = {}) => `
  <dialog class="modal" tabindex="-1" data-controller="modal" data-modal-toasts-value="toast-container"
          data-action="click->modal#backdropClick close->modal#closed">
    <div class="modal__backdrop"></div>
    <div class="modal__dialog" data-modal-target="dialog">
      <button class="modal__close" data-action="click->modal#close">Close</button>
      <h2 class="modal__title">${title}</h2>
      <div class="modal__body">
        <input type="hidden" name="authenticity_token">
        ${fields}
      </div>
      <footer class="modal__footer"><button class="modal__btn--cancel" data-action="click->modal#close">Cancel</button></footer>
    </div>
    <div class="toast-container" data-modal-target="toasts"></div>
  </dialog>
`

let mounted
const pointer = { fine: false }

beforeEach(async () => {
  pointer.fine = false
  window.matchMedia = (query) => ({ media: query, matches: query === "(pointer: fine)" && pointer.fine })
  mounted = await mount("modal", ModalController, PAGE)
})

// Stopping Stimulus disconnects nothing, and where the focus goes back to
// is kept from one modal to the next, so each test's modal is taken off the
// page first, as a visit to another page would.
afterEach(async () => {
  frame().replaceChildren()
  await settle()
  mounted.stop()
})

const frame = () => document.getElementById("modals")
const dialog = () => document.querySelector("dialog.modal")
const pageToasts = () => document.getElementById("toast-container")

async function open(html = modal()) {
  frame().innerHTML = html
  await settle()
}

async function press(selector) {
  document.querySelector(selector).click()
  await settle()
}

test("a modal opens as the browser's modal dialog", async () => {
  await open()

  assert.equal(dialog().open, true)
})

test("on a touch screen the dialog takes the focus, so no keyboard rises over it", async () => {
  await open()

  assert.equal(document.activeElement, dialog())
})

test("with a mouse the first field takes it, past the hidden ones", async () => {
  pointer.fine = true
  await open()

  assert.equal(document.activeElement.id, "title")
})

test("a form that comes back refused puts the focus on the field the server refused", async () => {
  pointer.fine = true
  await open(modal({ fields: `<input id="title"><input id="year" aria-invalid="true">` }))

  assert.equal(document.activeElement.id, "year")
})

test("a modal with no field focuses the dialog", async () => {
  pointer.fine = true
  await open(modal({ fields: "<p>Nothing to fill in</p>" }))

  assert.equal(document.activeElement, dialog())
})

test("closing takes the modal off the page and gives the focus back to what opened it", async () => {
  document.getElementById("opener").focus()
  await open()

  await press(".modal__btn--cancel")

  assert.equal(dialog(), null)
  assert.equal(document.activeElement.id, "opener")
})

test("a modal drawn again keeps where the focus goes back to", async () => {
  document.getElementById("opener").focus()
  await open()
  await open(modal({ title: "Edit book, with its errors" }))

  assert.equal(document.activeElement, dialog())
  await press(".modal__close")

  assert.equal(document.activeElement.id, "opener")
})

test("a modal drawn again after a press inside it keeps the focus on what is drawn again", async () => {
  await open(modal({ fields: `<a id="stop-1" href="#">Stop</a><a id="stop-2" href="#">Stop</a>` }))
  document.getElementById("stop-2").focus()

  await open(modal({ fields: `<a id="stop-1" href="#">Stop</a><a id="stop-2" href="#">Stop</a>` }))

  assert.equal(document.activeElement.id, "stop-2")
})

test("one that went with the redraw hands the focus to its fallback", async () => {
  await open(
    modal({ fields: `<a id="stop-1" href="#" data-focus-fallback="stop-2">Stop</a><a id="stop-2" href="#">Stop</a>` })
  )
  document.getElementById("stop-1").focus()

  await open(modal({ fields: `<a id="stop-2" href="#">Stop</a>` }))

  assert.equal(document.activeElement.id, "stop-2")
})

test("a field the server refused outranks what had the focus", async () => {
  pointer.fine = true
  await open(modal({ fields: `<input id="title"><button id="save">Save</button>` }))
  document.getElementById("save").focus()

  await open(modal({ fields: `<input id="title" aria-invalid="true"><button id="save">Save</button>` }))

  assert.equal(document.activeElement.id, "title")
})

test("a modal opened after one was closed starts afresh", async () => {
  await open(modal({ fields: `<a id="stop-1" href="#">Stop</a>` }))
  document.getElementById("stop-1").focus()
  await press(".modal__btn--cancel")

  await open(modal({ fields: `<a id="stop-1" href="#">Stop</a>` }))

  assert.equal(document.activeElement, dialog())
})

test("a modal closed by the server gives the focus back too", async () => {
  document.getElementById("opener").focus()
  await open()

  frame().innerHTML = ""
  await settle()

  assert.equal(document.activeElement.id, "opener")
})

test("what opened it, drawn again while the modal was open, gets the focus back by its id", async () => {
  document.getElementById("opener").focus()
  await open()

  document.getElementById("opener").outerHTML = `<button id="opener">Edit, redrawn</button>`
  await press(".modal__close")

  assert.equal(document.activeElement.textContent, "Edit, redrawn")
})

test("what opened it is left alone when it can no longer be seen", async () => {
  document.getElementById("folded-entry").focus()
  await open()

  await press(".modal__close")

  assert.equal(document.activeElement, document.body)
})

test("a click on the backdrop closes the modal, and one inside it doesn't", async () => {
  await open()

  await press(".modal__title")
  assert.ok(dialog())

  // Away from the dialog, which jsdom lays out as a box of no size at the corner.
  document
    .querySelector(".modal__backdrop")
    .dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: 40, clientY: 40 }))
  await settle()
  assert.equal(dialog(), null)
})

test("toasts show inside the open modal, and go back to the page when it closes", async () => {
  pageToasts().insertAdjacentHTML("beforeend", `<div class="toast toast--success">Saved</div>`)
  await open()

  pageToasts().insertAdjacentHTML("beforeend", `<div class="toast toast--alert">Refused</div>`)
  await settle()

  const shown = () => Array.from(dialog().querySelectorAll(".toast")).map((toast) => toast.textContent)
  assert.deepEqual(shown(), ["Saved", "Refused"])
  assert.equal(pageToasts().querySelectorAll("template").length, 1, "a failed request's toast stays ready on the page")

  await press(".modal__close")

  assert.deepEqual(
    Array.from(pageToasts().querySelectorAll(":scope > .toast")).map((toast) => toast.textContent),
    ["Saved", "Refused"]
  )
})
