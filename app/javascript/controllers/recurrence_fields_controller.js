import { Controller } from "@hotwired/stimulus"

// The recurrence fields of a series' form: the interval, the days of the
// week and the end show only for the frequencies they apply to, and of the
// end's fields only the one its choice asks for. A field not shown is
// disabled too, so it is neither sent nor required. A count of a series
// that happens every day is worded in days, of any other in times.
export default class extends Controller {
  static targets = ["details", "weeklyDays", "interval", "endsBy", "endsCount", "endsValue"]

  connect() {
    this.toggle()
  }

  toggle() {
    const frequency = this.element.querySelector("[data-recurrence-frequency]")?.value
    const recurring = Boolean(frequency) && frequency !== "none"
    const counted = frequency === "daily" && Number(this.intervalTarget.value || 1) === 1 ? "days" : "times"

    this.detailsTarget.hidden = !recurring
    this.weeklyDaysTarget.hidden = frequency !== "weekly"
    this.endsCountTarget.textContent = this.endsCountTarget.dataset[counted]
    this.endsValueTargets.forEach((field) => {
      const chosen = field.dataset.endsBy === this.endsByTarget.value
      const shown = recurring && chosen && (!field.dataset.counts || field.dataset.counts === counted)
      field.hidden = !shown
      field.querySelectorAll("input").forEach((input) => (input.disabled = !shown))
    })
  }
}
