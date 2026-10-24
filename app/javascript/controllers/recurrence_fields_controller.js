import { Controller } from "@hotwired/stimulus"

// The recurrence fields of a series' form: the interval, the days of the
// week and the end show only for the frequencies they apply to, and of the
// end's fields only the one its choice asks for. A field not shown is
// disabled too, so it is neither sent nor required.
export default class extends Controller {
  static targets = ["details", "weeklyDays", "endsBy", "endsValue"]

  connect() {
    this.toggle()
  }

  toggle() {
    const frequency = this.element.querySelector("[data-recurrence-frequency]")?.value
    const recurring = Boolean(frequency) && frequency !== "none"

    this.detailsTarget.hidden = !recurring
    this.weeklyDaysTarget.hidden = frequency !== "weekly"
    this.endsValueTargets.forEach((field) => {
      const shown = recurring && field.dataset.endsBy === this.endsByTarget.value
      field.hidden = !shown
      field.querySelectorAll("input").forEach((input) => (input.disabled = !shown))
    })
  }
}
