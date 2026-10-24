import { Controller } from "@hotwired/stimulus"
import { FloatingMenu } from "helpers/floating_menu"

// Every day's "+" on a page opens this one menu of the kinds of series
// (Views::Calendar::AddMenu), for the day pressed: the day is the menu's
// form's one field, and each kind sends it to its own form.
export default class extends Controller {
  static targets = ["menu", "date"]

  #menu = null

  connect() {
    this.#menu = new FloatingMenu(this.menuTarget)
  }

  disconnect() {
    this.#menu.close()
  }

  open({ currentTarget, params: { date } }) {
    if (this.#menu.isOpenFrom(currentTarget)) return this.#menu.close()

    this.dateTarget.value = date
    this.#menu.openAt(currentTarget)
  }

  // The kind's form opens over the page; the menu folds as it does.
  chosen() {
    this.#menu.close({ returnFocus: true })
  }

  // A page refresh that lands while the menu is open would morph it shut
  // and forget its day.
  holdWhileOpen(event) {
    if (this.#menu.isOpen) event.preventDefault()
  }
}
