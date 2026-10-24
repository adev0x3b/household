import { Controller } from "@hotwired/stimulus"

// The recurrence fields of a series' form: the interval and the days of
// the week show only for the frequencies they apply to.
export default class extends Controller {
  static targets = ["details", "weeklyDays"]

  connect() {
    this.toggle()
  }

  toggle() {
    const frequency = this.element.querySelector("[data-recurrence-frequency]")?.value
    const recurring = Boolean(frequency) && frequency !== "none"

    this.detailsTarget.hidden = !recurring
    this.weeklyDaysTarget.hidden = frequency !== "weekly"
  }
}
