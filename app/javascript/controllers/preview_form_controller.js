import { Controller } from "@hotwired/stimulus"

// The preview modal of the delivery console
// (Views::Admin::Deliveries::Modals::Preview). A branch other than the one
// dev runs wants fresh data, since its migrations may differ from what
// dev's database saw; the same branch again keeps what was set up there.
// The "fresh" box follows the branch typed, ticked when the branch stops
// being the current one and unticked when it is again, and the reader can
// still flip it in between.
export default class extends Controller {
  static targets = ["branch", "fresh"]
  static values = { current: String }

  connect() {
    this.same = this.sameAsCurrent()
  }

  changed() {
    const same = this.sameAsCurrent()
    if (same === this.same) return

    this.same = same
    this.freshTarget.checked = !same
  }

  sameAsCurrent() {
    const branch = this.branchTarget.value.trim()
    return branch === "" || branch === this.currentValue
  }
}
