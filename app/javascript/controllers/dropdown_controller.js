import { Controller } from "@hotwired/stimulus"

// A button that opens a small menu of its own (the bell, the account menu,
// an item's "more" menu, a dashboard's period). The button is the toggler
// target and the menu the menu target. It is a disclosure, not an ARIA
// menu: the menu's entries are links and buttons, reached with Tab like any
// others, and the button says only whether it is open. The menu closes on a
// click elsewhere, on Escape, when the focus leaves it, or when one of its
// entries says so; folding with the focus inside, it gives the focus back
// to its button. Where a menu sits is its stylesheet's business. Opening
// dispatches "dropdown:opened", for a menu whose content is read again each
// time (the bell). A menu that many buttons open, drawn once for the page,
// is a FloatingMenu instead (helpers/floating_menu.js).
export default class extends Controller {
  static targets = ["menu", "toggler"]

  // Listened for on the whole document while the menu is open, which is
  // why they are kept as fields: removing a listener needs the same function.
  #closeOutside = (event) => {
    if (!this.element.contains(event.target)) this.close()
  }

  #closeOnEscape = (event) => {
    if (event.key === "Escape") this.close()
  }

  // Tabbing past the last entry, or back before the button, leaves a menu
  // open over the page with nothing in it to act on. Focus that goes
  // nowhere (to the browser's own controls) leaves it as it is.
  #closeOnFocusOut = (event) => {
    const next = event.relatedTarget
    if (next && !this.element.contains(next)) this.close()
  }

  disconnect() {
    this.close()
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.menuTarget.classList.add("is-open")
    this.togglerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.#closeOutside, true)
    document.addEventListener("keydown", this.#closeOnEscape)
    this.element.addEventListener("focusout", this.#closeOnFocusOut)
    this.dispatch("opened")
  }

  // Left on an entry no longer seen, the focus would drop to the top of
  // the page, and a modal or a question the entry opened would have
  // nowhere to give it back to.
  close() {
    const focusInside = this.menuTarget.contains(document.activeElement)
    this.menuTarget.classList.remove("is-open")
    this.togglerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.#closeOutside, true)
    document.removeEventListener("keydown", this.#closeOnEscape)
    this.element.removeEventListener("focusout", this.#closeOnFocusOut)
    if (focusInside) this.togglerTarget.focus()
  }

  get isOpen() {
    return this.menuTarget.classList.contains("is-open")
  }
}
