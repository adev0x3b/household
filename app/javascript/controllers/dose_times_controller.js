import { Controller } from "@hotwired/stimulus"

// The doses of a day on a medication's form
// (Views::Medications::DoseTimesFields): a stepper that adds one dose or
// takes the last one away, each row an anchor (with breakfast…) or a clock
// time, and the hidden value that is sent for it. A row the user set is never
// rewritten: "+" appends one row with the next standard time for that many
// doses a day (the first of them not already on the list), "−" and the row's
// own button remove one.
export default class extends Controller {
  static targets = ["rows", "template", "count", "row"]
  static values = { defaults: Object, max: Number }

  connect() {
    this.rowTargets.forEach((row) => this.syncRow(row))
    this.renumber()
  }

  increment(event) {
    event.preventDefault()
    const count = this.rowTargets.length + 1
    if (count > this.maxValue) return

    this.addRow(this.nextEntry(count))
    this.renumber()
  }

  decrement(event) {
    event.preventDefault()
    this.rowTargets.at(-1)?.remove()
    this.renumber()
  }

  // The standard time to propose for one more dose: the first of the ISMP
  // times for `count` doses a day that no row has yet, else the last of them.
  nextEntry(count) {
    const entries = this.defaultsValue[count] || []
    const taken = new Set(this.rowTargets.map((row) => row.querySelector('[data-dose-times-target="value"]').value))
    return entries.find((entry) => !taken.has(entry)) || entries.at(-1) || ""
  }

  addRow(entry) {
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML)
    const row = this.rowsTarget.lastElementChild
    const select = row.querySelector('[data-dose-times-target="anchor"]')
    const time = row.querySelector('[data-dose-times-target="time"]')
    const isAnchor = Array.from(select.options).some((option) => option.value === entry)
    select.value = isAnchor ? entry : "custom"
    time.value = isAnchor ? "" : entry
    this.syncRow(row)
  }

  sync(event) {
    this.syncRow(event.target.closest('[data-dose-times-target="row"]'))
  }

  // The hidden value is the anchor's code, or the clock time typed.
  syncRow(row) {
    const select = row.querySelector('[data-dose-times-target="anchor"]')
    const time = row.querySelector('[data-dose-times-target="time"]')
    const value = row.querySelector('[data-dose-times-target="value"]')
    const custom = select.value === "custom"
    time.hidden = !custom
    time.disabled = !custom
    value.value = custom ? time.value : select.value
  }

  remove(event) {
    event.preventDefault()
    event.target.closest('[data-dose-times-target="row"]').remove()
    this.renumber()
  }

  renumber() {
    this.countTarget.textContent = this.rowTargets.length
  }
}
