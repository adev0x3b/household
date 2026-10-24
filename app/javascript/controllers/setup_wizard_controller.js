import { Controller } from "@hotwired/stimulus"

// The first setup (Views::Setup::Show): one form, shown a step at a time.
// Next checks the step's fields before moving on, Back keeps what was
// typed, a step that depends on a switch (data-setup-wizard-when, the
// switch's name) is skipped while it is off, and the last step lists every
// answer, each group with a way back to it, above Create. Nothing is sent
// until Create; without this controller every step shows at once.
export default class extends Controller {
  static targets = ["step", "review", "summary", "progress", "back", "next", "create"]
  static values = {
    start: Number,
    progress: String,
    on: String,
    off: String,
    set: String,
    unset: String,
    change: String
  }

  connect() {
    this.current = this.asked().includes(this.stepTargets[this.startValue]) ? this.startValue : 0
    this.progressTarget.hidden = false
    this.show()
  }

  next() {
    if (!this.checked(this.stepTargets[this.current])) return

    const following = this.asked().find((step) => this.stepTargets.indexOf(step) > this.current)
    this.go(this.stepTargets.indexOf(following))
  }

  back() {
    const earlier = this.asked().filter((step) => this.stepTargets.indexOf(step) < this.current)
    this.go(this.stepTargets.indexOf(earlier.at(-1)))
  }

  // Before the browser checks the form: a step that is skipped sends
  // nothing, and a field still wrong anywhere opens its step.
  create(event) {
    this.stepTargets.forEach((step) => this.skip(step, !this.asked().includes(step)))
    const wrong = this.asked().find((step) => !this.checked(step, { quietly: true }))
    if (!wrong) return

    event.preventDefault()
    this.go(this.stepTargets.indexOf(wrong))
    this.checked(wrong)
  }

  // Enter in a field moves on rather than sending the form from the middle.
  enter(event) {
    if (this.onReview || !(event.target instanceof HTMLInputElement)) return

    event.preventDefault()
    this.next()
  }

  // The steps the answers so far call for, the review last.
  asked() {
    return this.stepTargets.filter((step) => {
      const condition = step.querySelector("[data-setup-wizard-when]")
      if (!condition) return true

      const name = condition.dataset.setupWizardWhen
      const toggle = [...this.element.querySelectorAll('input[type="checkbox"]')].find((input) => input.name === name)
      return !toggle || toggle.checked
    })
  }

  get onReview() {
    return this.stepTargets[this.current] === this.reviewTarget
  }

  go(index) {
    this.current = index
    if (this.onReview) this.summarize()
    this.show()
    const title = this.stepTargets[this.current].querySelector(".panel__title")
    title?.setAttribute("tabindex", "-1")
    title?.focus({ preventScroll: true })
    this.element.scrollIntoView({ block: "start" })
  }

  show() {
    const asked = this.asked()
    this.stepTargets.forEach((step, index) => (step.hidden = index !== this.current))
    const position = asked.indexOf(this.stepTargets[this.current])
    this.progressTarget.textContent = this.progressValue
      .replace("%{current}", position + 1)
      .replace("%{total}", asked.length)
      .replace("%{title}", this.titleOf(this.stepTargets[this.current]))
    this.backTarget.hidden = position === 0
    this.nextTarget.hidden = this.onReview
    this.createTarget.hidden = !this.onReview
  }

  // A step of several cards names itself; the others are their card.
  titleOf(step) {
    const named = step.querySelector("[data-setup-wizard-title]")
    if (named) return named.dataset.setupWizardTitle

    return step.querySelector(".panel__title")?.textContent.trim() ?? ""
  }

  // Whether every field of a step takes what was typed; unless quietly,
  // the browser says what the first wrong one needs.
  checked(step, { quietly = false } = {}) {
    const wrong = this.controls(step).find((control) => !control.checkValidity())
    if (wrong && !quietly) {
      if (step.hidden) this.go(this.stepTargets.indexOf(step))
      wrong.reportValidity()
    }
    return !wrong
  }

  controls(step) {
    return [...step.querySelectorAll("input, select, textarea")].filter(
      (control) => !control.disabled && control.type !== "hidden"
    )
  }

  // A skipped step's fields are disabled so they are neither checked nor
  // sent; the ones the page itself disabled stay so.
  skip(step, skipped) {
    step.querySelectorAll("input, select, textarea").forEach((control) => {
      if (skipped && !control.disabled) {
        control.disabled = true
        control.dataset.setupWizardSkipped = ""
      } else if (!skipped && "setupWizardSkipped" in control.dataset) {
        control.disabled = false
        delete control.dataset.setupWizardSkipped
      }
    })
  }

  // Every answer of the steps asked, one group per step under its title.
  summarize() {
    this.summaryTarget.replaceChildren(
      ...this.asked()
        .filter((step) => step !== this.reviewTarget)
        .map((step) => this.group(step))
        .filter(Boolean)
    )
  }

  group(step) {
    const rows = this.answers(step)
    if (rows.length === 0) return null

    const section = document.createElement("section")
    section.className = "setup__summary-group"
    const heading = document.createElement("h3")
    heading.className = "setup__summary-title"
    heading.textContent = this.titleOf(step)
    const change = document.createElement("button")
    change.type = "button"
    change.className = "button is-small is-text setup__summary-change"
    change.textContent = this.changeValue
    change.setAttribute("aria-label", `${this.changeValue}: ${heading.textContent}`)
    change.addEventListener("click", () => this.go(this.stepTargets.indexOf(step)))
    const list = document.createElement("dl")
    list.className = "setup__summary-list"
    rows.forEach(([name, value]) => {
      const term = document.createElement("dt")
      term.textContent = name
      const detail = document.createElement("dd")
      detail.textContent = value
      list.append(term, detail)
    })
    section.append(heading, change, list)
    return section
  }

  answers(step) {
    return [...step.querySelectorAll("input, select, textarea")]
      .filter((control) => control.type !== "hidden" && !(control.type === "radio" && !control.checked))
      .filter((control) => {
        const hiddenGroup = control.closest("[hidden]")
        return !hiddenGroup || hiddenGroup === step
      })
      .map((control) => [this.nameOf(control), this.valueOf(control)])
  }

  nameOf(control) {
    if (control.type === "radio") return control.closest("fieldset")?.querySelector("legend")?.textContent.trim() ?? ""

    const label = control.labels?.[0]
    if (!label) return control.getAttribute("aria-label") ?? ""

    const choice = label.querySelector("strong")
    return (choice ?? label.childNodes[0]).textContent.trim()
  }

  valueOf(control) {
    if (control.type === "checkbox") return control.checked ? this.onValue : this.offValue
    if (control.type === "password") return control.value ? this.setValue : control.placeholder || this.unsetValue
    if (control.type === "radio") {
      return control.labels?.[0]?.querySelector("strong")?.textContent.trim() ?? control.value
    }
    if (control instanceof HTMLSelectElement) return control.selectedOptions[0]?.textContent.trim() ?? ""
    return control.value || control.placeholder || "—"
  }
}
