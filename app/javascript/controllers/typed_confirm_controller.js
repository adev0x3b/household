import { Controller } from "@hotwired/stimulus"

// A dangerous action's modal (a rollback, a release with downtime): the
// submit stays disabled until the reader types the phrase, the version's
// short sha, exactly. A picker in the form (the rollback's versions)
// changes the phrase through `pick`.
export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { phrase: String }

  connect() {
    this.check()
  }

  // The phrase can change under a morph as well as from a picker.
  phraseValueChanged() {
    if (this.element.isConnected) this.check()
  }

  pick(event) {
    const phrase = event.target.dataset.phrase
    if (phrase) this.phraseValue = phrase
  }

  check() {
    const typed = this.inputTarget.value.trim().toLowerCase()
    const matches = typed.length > 0 && typed === this.phraseValue.toLowerCase()

    this.submitTarget.disabled = !matches
    this.inputTarget.setAttribute("aria-invalid", typed.length > 0 && !matches ? "true" : "false")
  }
}
