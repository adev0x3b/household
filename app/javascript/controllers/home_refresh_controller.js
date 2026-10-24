import { Controller } from "@hotwired/stimulus"

// A change to a series arrives as one message per day it touches, so a
// burst is waited out and read once.
const SETTLE = 300

// Keeps a home dashboard page true after something on it changed: a modal
// saved or an item ticked off here, or a day changed elsewhere, which the
// overview hears from its today card's calendar subscription. The page's
// content sits in one turbo frame (the element this controller is on), so
// reloading that frame refreshes every figure and list without moving the
// reader, closing a modal or losing a toast.
export default class extends Controller {
  #timer = null

  connect() {
    document.addEventListener("turbo:submit-end", this.#reloadAfterSubmit)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.#reloadAfterSubmit)
    clearTimeout(this.#timer)
  }

  // Only what changes data: a GET form (the period, the member) navigates.
  // Listened for on the document, which is why it is kept as a field:
  // removing a listener needs the same function.
  #reloadAfterSubmit = (event) => {
    const method = (event.target.getAttribute("method") || "get").toLowerCase()
    if (method === "get" || !event.detail.success) return

    this.reload()
  }

  reload() {
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => this.#reloadFrame(), SETTLE)
  }

  // The URL may have moved since the last reload (a page of the next 7
  // days advances it): reload from where the reader is now.
  #reloadFrame() {
    const url = window.location.href
    if (this.element.getAttribute("src") === url) {
      this.element.reload()
    } else {
      this.element.setAttribute("src", url)
    }
  }
}
