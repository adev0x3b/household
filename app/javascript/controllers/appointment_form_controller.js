import { Controller } from "@hotwired/stimulus"

// The appointment form's wording follows its kind: "Provider" for a
// medical visit, "With" for the rest, and placeholders to match. Each
// kind's wording comes on its <option> (Appointment::Kind), and this swaps
// it in when the kind changes.
export default class extends Controller {
  static targets = ["kind", "counterpartLabel", "counterpartInput", "titleInput", "locationInput"]

  connect() {
    this.syncKind()
  }

  syncKind() {
    const option = this.kindTarget.selectedOptions[0]
    if (!option) return

    this.counterpartLabelTarget.textContent = option.dataset.label
    this.counterpartInputTarget.placeholder = option.dataset.placeholder
    this.titleInputTarget.placeholder = option.dataset.titlePlaceholder
    this.locationInputTarget.placeholder = option.dataset.locationPlaceholder
  }
}
