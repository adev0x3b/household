import { Controller } from "@hotwired/stimulus"

// Opens the calendar on today: when the month being viewed holds today's
// day card, the page starts scrolled to it instead of the 1st.
//
// Lives on the calendar container, not on the card: day cards are replaced
// by Turbo Streams after every change, and a controller on the card would
// scroll the reader back on each of them. Only connect() scrolls: moving to
// another month is a page refresh that morphs the container in place (the
// reader keeps their scroll), so coming back to this month doesn't jump.
export default class extends Controller {
  static targets = ["today"]

  connect() {
    // Going back or forward keeps the position the reader left.
    if (!this.hasTodayTarget || this.restoring) return

    // After Turbo's own scroll for the visit (to the top), which runs once
    // the page is rendered.
    this.frame = requestAnimationFrame(() => {
      this.todayTarget.scrollIntoView({ block: "start", behavior: "instant" })
    })
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }

  get restoring() {
    return window.Turbo?.navigator.currentVisit?.action === "restore"
  }
}
