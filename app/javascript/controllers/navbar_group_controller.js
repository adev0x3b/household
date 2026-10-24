import { Controller } from "@hotwired/stimulus"

// A group of links in the navigation drawer (Views::Layouts::Navbar::Sheet),
// folded or unfolded by its header. The server renders the group holding
// the current page open, and it gets its height as soon as it connects.
// Folded, its links are inert: hidden only by their height, they would
// still take the focus and be read out.
export default class extends Controller {
  static targets = ["children", "toggle"]

  connect() {
    if (this.element.classList.contains("is-open")) this.expand(true)
  }

  toggle() {
    this.expand(this.element.classList.toggle("is-open"))
  }

  // The height is set outright because max-height is what the fold animates;
  // "auto" would snap.
  expand(open) {
    this.childrenTarget.style.maxHeight = open ? `${this.childrenTarget.scrollHeight}px` : null
    this.childrenTarget.inert = !open
    this.toggleTarget.setAttribute("aria-expanded", open ? "true" : "false")
  }
}
