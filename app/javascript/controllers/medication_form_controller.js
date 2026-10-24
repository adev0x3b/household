import { Controller } from "@hotwired/stimulus"

// The medication form shows only what its answers call for: the area and
// side of an injection, and for a dose that exists, why it was skipped or
// when it was taken. A hidden field is also disabled, so it is not sent.
// The server checks everything again.
export default class extends Controller {
  static targets = [
    "kind",
    "areaSection",
    "areaSelect",
    "sideSection",
    "sideSelect",
    "status",
    "reasonSection",
    "reasonSelect",
    "takenAtSection",
    "takenAtInput"
  ]

  connect() {
    this.syncKind()
    this.syncStatus()
  }

  syncKind() {
    const injection = this.kindTarget.value === "injection"

    this.areaSectionTarget.hidden = !injection
    this.areaSelectTarget.disabled = !injection
    this.sideSectionTarget.hidden = !injection
    this.sideSelectTarget.disabled = !injection
  }

  // The status and what goes with it are on the form of a dose that
  // exists, not of a new series.
  syncStatus() {
    if (!this.hasStatusTarget) return

    const status = this.statusTarget.value
    const skipped = status === "skipped"
    const taken = status === "completed"

    this.reasonSectionTarget.hidden = !skipped
    this.reasonSelectTarget.disabled = !skipped
    this.takenAtSectionTarget.hidden = !taken
    this.takenAtInputTarget.disabled = !taken
    if (taken && !this.takenAtInputTarget.value) this.takenAtInputTarget.value = this.localNow()
  }

  // "YYYY-MM-DDTHH:MM" on this device's clock, which is what a
  // datetime-local input takes.
  localNow() {
    const now = new Date()
    now.setSeconds(0, 0)
    const offset = now.getTimezoneOffset() * 60000
    return new Date(now - offset).toISOString().slice(0, 16)
  }
}
