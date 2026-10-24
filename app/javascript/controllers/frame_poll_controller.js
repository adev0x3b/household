import { Controller } from "@hotwired/stimulus"

// Keeps the surrounding <turbo-frame> fresh while something runs elsewhere
// (an eval run in its own process). Lives on an element *inside* the frame,
// so each reload brings a new controller with the new `active` value — the
// server renders active: false once the work is done, and polling stops.
export default class extends Controller {
  static values = { url: String, active: Boolean, interval: { type: Number, default: 3000 } }

  connect() {
    if (this.activeValue) this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  poll() {
    const frame = this.element.closest("turbo-frame")
    if (!frame) return

    if (frame.src) frame.reload()
    else frame.src = this.urlValue
  }
}
