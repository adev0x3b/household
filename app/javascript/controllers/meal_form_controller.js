import { Controller } from "@hotwired/stimulus"

// A meal at home picks recipes; eating out or ordering in has a title and
// a cost instead. The section not in use is hidden and its fields
// disabled, so they are not sent. The server checks everything again.
export default class extends Controller {
  static targets = ["kind", "homeSection", "awaySection"]

  connect() {
    this.syncKind()
  }

  syncKind() {
    const home = this.kindTarget.value === "home"

    this.toggle(this.homeSectionTargets, home)
    this.toggle(this.awaySectionTargets, !home)
  }

  // A row's id inputs tagged for "this day / the whole series" are
  // apply_to_controller.js's to enable and disable.
  toggle(sections, shown) {
    sections.forEach((section) => {
      section.hidden = !shown
      section.querySelectorAll("input:not([data-apply-to-scope]), select, textarea").forEach((field) => {
        field.disabled = !shown
      })
    })
  }
}
