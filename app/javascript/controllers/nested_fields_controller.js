import { Controller } from "@hotwired/stimulus"

// A variable-length list of rows on a form with nested attributes (a lab
// result's entries, a recipe's steps, what a dose draws on), drawn by
// Components::NestedFields. A row is added from the template. A row with a
// destroy flag is hidden and marked rather than taken out, so the server
// deletes it, or drops it if it was never saved; a row of a list saved as a
// whole has no flag, and is taken out.
export default class extends Controller {
  static targets = ["container", "template", "row", "destroyField"]

  connect() {
    this.nextIndex = 0
  }

  // Strong parameters keep a nested row only under a numeric key, so a new
  // row's index counts down from zero: unique on the form, and never one
  // the record's own rows use.
  add(event) {
    event.preventDefault()

    this.nextIndex -= 1
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, this.nextIndex)
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()

    const row = this.rowTargets.find((candidate) => candidate.contains(event.currentTarget))
    if (!row) return

    const destroyField = this.destroyFieldTargets.find((field) => row.contains(field))
    if (destroyField) {
      destroyField.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
  }
}
