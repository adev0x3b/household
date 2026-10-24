import { Controller } from "@hotwired/stimulus"

// Sends its form when a field changes: a choice (a select) once it is made,
// or a search box after a pause in typing.
//
// A select changes on every arrow key while it is closed (on Windows and
// Linux), one step a press, and sending each step would load a page per
// step on the way to the one wanted. A step taken by key is held until
// Enter or until the reader leaves the select; a choice made in its list
// (a click, a tap, Enter there) is sent at once.
//
// A search form must target a turbo frame holding only the results, never
// one that holds the form: a response that re-rendered the input would
// overwrite what was typed while the request was in flight. Turbo aborts
// the frame's previous submission when a new one starts, so a slow, stale
// answer cannot land after a newer one.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  disconnect() {
    this.cancel()
  }

  submit() {
    this.cancel()
    this.held = false
    this.element.requestSubmit()
  }

  // The select's own list takes the keys while it is open, so a keydown
  // reaching the select means it is closed and the key steps through it.
  keydown(event) {
    if (event.key === "Enter" && this.held) {
      event.preventDefault()
      this.submit()
    } else if (!event.altKey) {
      this.stepping = true
    }
  }

  keyup() {
    this.stepping = false
  }

  choose() {
    if (this.stepping) {
      this.held = true
    } else {
      this.submit()
    }
  }

  leave() {
    if (this.held) this.submit()
  }

  search() {
    this.cancel()
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  // Wired to the form's own submit event: pressing Enter submits right away,
  // so drop the pending debounced submit instead of sending it twice.
  cancel() {
    clearTimeout(this.timeout)
  }
}
