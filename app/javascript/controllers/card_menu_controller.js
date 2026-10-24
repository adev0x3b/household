import { Controller } from "@hotwired/stimulus"
import { FloatingMenu } from "helpers/floating_menu"
import { interpolate } from "helpers/interpolate"

// The "more" of every calendar card on a page opens this one menu
// (Views::Calendar::CardMenu), filled for the card pressed: the statuses
// its day can take and its deletes, each part only where the viewer may
// use it, the whole series offered only for one that repeats, and the
// words of a request to the owner when they must say yes.
export default class extends Controller {
  static targets = ["menu", "statusForm", "deleteForm", "entry"]

  #menu = null

  connect() {
    this.#menu = new FloatingMenu(this.menuTarget)
  }

  disconnect() {
    this.#menu.close()
  }

  open({ currentTarget, params: { repeats, deleteUrl, deleteOwner, statusUrl, statuses = [], statusOwner } }) {
    if (this.#menu.isOpenFrom(currentTarget)) return this.#menu.close()

    this.#fill(this.statusFormTarget, statusUrl, statusOwner)
    this.#fill(this.deleteFormTarget, deleteUrl, deleteOwner)
    this.#entriesOf(this.statusFormTarget).forEach((entry) => (entry.hidden = !statuses.includes(entry.value)))
    this.#entriesOf(this.deleteFormTarget).find((entry) => entry.value === "series").hidden = !repeats
    this.#menu.openAt(currentTarget)
  }

  // Chosen, a press folds the menu, so a delete's question isn't answered
  // over it, and the card's button keeps the focus behind it.
  chosen() {
    this.#menu.close({ returnFocus: true })
  }

  // A page refresh that lands while the menu is open would morph it back
  // to its empty form under the reader's finger.
  holdWhileOpen(event) {
    if (this.#menu.isOpen) event.preventDefault()
  }

  // A part of the menu goes to the card's address for it, or is hidden
  // when the card gave none.
  #fill(form, url, owner) {
    form.hidden = !url
    if (!url) return

    form.action = url
    this.#entriesOf(form).forEach((entry) => this.#word(entry, owner))
  }

  #entriesOf(form) {
    return this.entryTargets.filter((entry) => form.contains(entry))
  }

  #word(entry, owner) {
    const { label, confirm, askLabel, askConfirm } = entry.dataset

    entry.querySelector("span").textContent = owner ? interpolate(askLabel, { name: owner }) : label
    if (confirm) entry.dataset.turboConfirm = owner ? interpolate(askConfirm, { name: owner }) : confirm
  }
}
