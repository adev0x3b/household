import { Controller } from "@hotwired/stimulus"
import { ScrollLock } from "helpers/scroll_lock"
import { replacementFor } from "helpers/focus_keeper"

// Where the focus was when a modal opened. A modal drawn again, with its
// errors or at its next step, is a new modal each time, so this outlives
// each one, and the focus goes back there once the last of them is gone.
let opener = null

// What had the focus in a modal drawn again, for the one drawn in its place:
// a press inside it (a person taken off a list) keeps the focus on what is
// drawn again, or on what takes its place.
let focusedBeforeRedraw = null

// A modal (Components::Modal), shown as the browser's modal dialog: the
// page behind it can't be reached and stays put, Escape and the back
// gesture close it, and so do its buttons and its backdrop. Closing it
// takes it off the page.
export default class extends Controller {
  static targets = ["dialog", "toasts"]
  static values = { toasts: String }

  #scrollLock = new ScrollLock()
  #focused = null
  #toastsArriving = new MutationObserver(() => this.#takeToasts())

  connect() {
    if (!opener) opener = document.activeElement
    if (!this.element.open) this.element.showModal()
    this.#scrollLock.hold()
    this.#takeToasts()
    if (this.pageToasts) this.#toastsArriving.observe(this.pageToasts, { childList: true })
    this.element.addEventListener("focusin", this.#remember)
    this.focusFirst()
  }

  disconnect() {
    this.element.removeEventListener("focusin", this.#remember)
    this.#toastsArriving.disconnect()
    this.#giveToastsBack()
    this.#scrollLock.release()
    if (this.#anotherModalOpen) focusedBeforeRedraw = this.#focused
    else this.#returnFocus()
  }

  close() {
    this.element.close()
  }

  // However the dialog was closed, by a button, Escape or the browser.
  closed() {
    this.element.remove()
  }

  // A form's first field is where a keyboard starts, or the one the server
  // refused when the form comes back. A touch screen would raise its
  // keyboard over half the modal for a field nobody tapped, so there the
  // dialog itself takes the focus, which also has it read out by name. A
  // modal drawn again after a press inside it keeps the focus where it was,
  // short of a refused field. A field the form marks autofocus already has
  // it, from the browser.
  focusFirst() {
    if (this.element.contains(document.activeElement) && document.activeElement.autofocus) return

    const field = window.matchMedia("(pointer: fine)").matches ? this.firstField() : null
    const kept = this.#keptThroughRedraw()
    ;((field?.getAttribute("aria-invalid") === "true" && field) || kept || field || this.element).focus()
  }

  firstField() {
    const fields = Array.from(this.dialogTarget.querySelectorAll(".modal__body :is(input, select, textarea)")).filter(
      (field) => field.type !== "hidden" && !field.disabled && field.getClientRects().length > 0
    )
    return fields.find((field) => field.getAttribute("aria-invalid") === "true") || fields[0]
  }

  #remember = (event) => {
    this.#focused = event.target
  }

  // The element now under the id of what had the focus in the modal this
  // one replaced, or under one of its fallbacks, if it is in this one.
  #keptThroughRedraw() {
    const element = focusedBeforeRedraw
    focusedBeforeRedraw = null
    if (!element) return null

    const kept = replacementFor(element, document)
    return kept && this.element.contains(kept) ? kept : null
  }

  // A click on the backdrop, or above it on the top bar, which is the
  // dialog's own backdrop, closes the modal.
  backdropClick(event) {
    if (this.clickInsideDialog(event)) return

    this.close()
  }

  // A click reaching the backdrop still counts as the dialog's when its
  // point lies within the dialog's bounds, as a click on a native picker
  // drawn over the backdrop does.
  clickInsideDialog(event) {
    if (
      event.target instanceof Node &&
      (this.dialogTarget.contains(event.target) || this.toastsTarget.contains(event.target))
    ) {
      return true
    }

    const { clientX, clientY } = event
    if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) return false

    const bounds = this.dialogTarget.getBoundingClientRect()
    return clientX >= bounds.left && clientX <= bounds.right && clientY >= bounds.top && clientY <= bounds.bottom
  }

  // The modal drawn in this one's place, which is already on the page when
  // this one is taken off.
  get #anotherModalOpen() {
    return Array.from(document.querySelectorAll(`[data-controller~="${this.identifier}"]`)).some(
      (element) => element !== this.element
    )
  }

  get pageToasts() {
    return document.getElementById(this.toastsValue)
  }

  // Only the toasts themselves: the page's container also keeps the
  // templates of the toasts a failed request shows.
  #takeToasts() {
    this.#toastsIn(this.pageToasts).forEach((toast) => this.toastsTarget.append(toast))
  }

  #giveToastsBack() {
    const page = this.pageToasts
    if (page) this.#toastsIn(this.toastsTarget).forEach((toast) => page.append(toast))
  }

  #toastsIn(container) {
    return container ? Array.from(container.children).filter((child) => child.classList.contains("toast")) : []
  }

  // Unless what had the focus is gone with the modal, or hidden by now, as
  // the entry of a menu that has folded. One a live change drew again while
  // the modal was open (a day card a save broadcast) is found by its id.
  #returnFocus() {
    const element = opener
    opener = null
    if (!(element instanceof HTMLElement)) return

    const target = element.isConnected ? element : replacementFor(element, document)
    if (target?.isConnected && target.getClientRects().length > 0) target.focus({ preventScroll: true })
  }
}
