import { Controller } from "@hotwired/stimulus"
import { FloatingMenu } from "helpers/floating_menu"
import { interpolate } from "helpers/interpolate"

// The "more" of every calendar card on a page opens this one menu
// (Views::Calendar::CardMenu), filled for the card pressed: its day's
// address, the whole series offered only for one that repeats, and the
// words of a request to the owner when they must say yes.
export default class extends Controller {
  static targets = ["menu", "form", "entry"]

  #menu = null

  connect() {
    this.#menu = new FloatingMenu(this.menuTarget)
  }

  disconnect() {
    this.#menu.close()
  }

  open({ currentTarget, params: { url, repeats, owner } }) {
    if (this.#menu.isOpenFrom(currentTarget)) return this.#menu.close()

    this.formTarget.action = url
    this.entryTargets.forEach((entry) => this.#word(entry, owner))
    this.entryTargets.find((entry) => entry.value === "series").hidden = !repeats
    this.#menu.openAt(currentTarget)
  }

  // Chosen, a delete asks first: the menu folds, so the question isn't
  // answered over it, and the card's button keeps the focus behind it.
  chosen() {
    this.#menu.close({ returnFocus: true })
  }

  // A page refresh that lands while the menu is open would morph it back
  // to its empty form under the reader's finger.
  holdWhileOpen(event) {
    if (this.#menu.isOpen) event.preventDefault()
  }

  #word(entry, owner) {
    const { label, confirm, askLabel, askConfirm } = entry.dataset

    entry.querySelector("span").textContent = owner ? interpolate(askLabel, { name: owner }) : label
    entry.dataset.turboConfirm = owner ? interpolate(askConfirm, { name: owner }) : confirm
  }
}
