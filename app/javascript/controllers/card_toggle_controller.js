import { Controller } from "@hotwired/stimulus"

// A card body shown on request (Components::Card), folded and unfolded by its button.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  toggle() {
    const expanded = this.triggerTarget.getAttribute("aria-expanded") === "true"

    this.triggerTarget.setAttribute("aria-expanded", String(!expanded))
    this.panelTarget.hidden = expanded
  }
}
