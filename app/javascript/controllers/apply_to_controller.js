import { Controller } from "@hotwired/stimulus"

// "This day only / The whole series" on the form of a day of a recurring
// series (Views::Occurrences::DayForm#render_apply_to). Some inputs make
// sense for one choice only: a list's row (what a dose uses, a meal's
// recipes) has a different id on the day's own list and on the series',
// and a payment's housemate is the series'. They are tagged
// data-apply-to-scope="day" or "series", and only the chosen scope's are
// sent. An input this controller disabled is marked data-apply-to-held,
// and only those are enabled again: another controller may have disabled
// an input for a reason of its own.
export default class extends Controller {
  static targets = ["choice"]

  // After the form's other controllers have set their fields up.
  connect() {
    queueMicrotask(() => this.sync())
  }

  sync() {
    const chosen = this.choiceTarget.value
    this.element.querySelectorAll("[data-apply-to-scope]").forEach((input) => {
      if (input.dataset.applyToScope === chosen) {
        if (input.dataset.applyToHeld) {
          input.disabled = false
          delete input.dataset.applyToHeld
        }
      } else if (!input.disabled) {
        input.disabled = true
        input.dataset.applyToHeld = "1"
      }
    })
  }
}
