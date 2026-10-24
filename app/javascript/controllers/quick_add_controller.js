import { Controller } from "@hotwired/stimulus"

// A list's quick-add bar (Views::GroceryListItems::QuickAdd). The server
// answers an add with the list's regions, never with this form, so the
// input is still here afterwards: on success it is cleared and keeps the
// focus for the next item; on a failure (a duplicate, a blank name — the
// server answers 422) the text stays to be corrected.
export default class extends Controller {
  static targets = ["input"]

  reset(event) {
    if (!event.detail.success) return

    this.inputTarget.value = ""
    this.inputTarget.focus()
  }
}
