import { Controller } from "@hotwired/stimulus"
import { interpolate } from "helpers/interpolate"

// A modal's form (Components::Form): a required field still missing is
// marked and says so under itself, once the reader has filled it in and
// left it, or has pressed Save. Save always answers: with something
// missing, it sends nothing and takes the focus to the first field to fill.
// Nothing is red before the reader has done anything, and a form the
// server refused shows every missing field at once. Required fields the
// reader cannot see (a section hidden for the current choice) do not count,
// as they cannot be filled.
export default class extends Controller {
  static values = { fieldRequired: String, submitted: Boolean }

  // The fields the reader has changed, and those of them they have left.
  #changed = new Set()
  #left = new Set()

  connect() {
    this.refresh()
  }

  refresh(event) {
    if (event?.type === "input" || event?.type === "change") this.#changed.add(event.target)

    const missing = this.missingFields()
    this.requiredFields().forEach((field) => this.#tell(field, missing.includes(field) && this.#toldOf(field)))
  }

  leave(event) {
    if (!this.#changed.has(event.target)) return

    this.#left.add(event.target)
    this.refresh()
  }

  // A button with formnovalidate (a lookup that fills the form) goes through
  // whatever is still missing; Save waits for every field. Blank space in a
  // text field passes the browser's own check, so it is stopped here.
  beforeSubmit(event) {
    if (event.submitter?.hasAttribute("formnovalidate")) return

    const missing = this.missingFields()
    if (missing.length === 0) return

    event.preventDefault()
    this.#refuse(missing)
  }

  // The browser checks the fields before the form is sent, and would show a
  // bubble of its own, in its own language, on the first one it refuses. A
  // missing field is said under itself instead; a field it refuses for
  // another reason (a number under its minimum) keeps the browser's bubble.
  invalid(event) {
    const missing = this.missingFields()
    if (!missing.includes(event.target)) return

    event.preventDefault()
    this.#refuse(missing)
  }

  missingFields() {
    return this.requiredFields().filter((field) => this.isMissing(field))
  }

  requiredFields() {
    return Array.from(this.element.querySelectorAll("[required]")).filter((field) => this.canBeFilled(field))
  }

  canBeFilled(field) {
    if (!(field instanceof HTMLElement) || field.disabled || field.type === "hidden") return false
    return field.getClientRects().length > 0
  }

  // Blank space in a text field is not an answer, though the browser would
  // take it. The field's validity is read rather than checked: checking
  // fires an invalid event, which this controller answers by asking again.
  isMissing(field) {
    if (this.takesText(field) && field.value.trim() === "") return true
    return !field.validity.valid
  }

  takesText(field) {
    return (
      field instanceof HTMLTextAreaElement ||
      (field instanceof HTMLInputElement &&
        !["checkbox", "radio", "number", "date", "time", "datetime-local"].includes(field.type))
    )
  }

  // The field's label as the user reads it, without the required mark and
  // the screen-reader text; the field's name when it has no label.
  nameOf(field) {
    const label = field.closest(".field")?.querySelector("label")
    if (!label) return field.name

    const copy = label.cloneNode(true)
    copy.querySelectorAll(".modal__required-indicator, .is-sr-only").forEach((node) => node.remove())
    return copy.textContent.replace(/\s+/g, " ").trim() || field.name
  }

  #refuse(missing) {
    this.submittedValue = true
    this.refresh()
    missing[0].focus()
  }

  #toldOf(field) {
    return this.submittedValue || this.#left.has(field)
  }

  // Each field keeps a hidden line for this (Components::Field), which the
  // control points to while it shows, so a screen reader reading the control
  // hears it. A control drawn outside a field is only marked. What the
  // server refused in the field stays said, and keeps the control invalid.
  #tell(field, missing) {
    const wrapper = field.closest(".field")
    wrapper?.classList.toggle("is-missing", missing)

    if (missing || wrapper?.classList.contains("is-invalid")) field.setAttribute("aria-invalid", "true")
    else field.removeAttribute("aria-invalid")

    const line = wrapper?.querySelector(".modal__field-tooltip")
    if (!line) return

    line.hidden = !missing
    line.textContent = missing ? interpolate(this.fieldRequiredValue, { field: this.nameOf(field) }) : ""
    describe(field, line.id, missing)
  }
}

// Adds an id to the ids that describe a control, or takes it away, keeping
// the others (what the server refused, a hint).
function describe(control, id, shown) {
  if (!id) return

  const ids = (control.getAttribute("aria-describedby") || "").split(/\s+/).filter((each) => each && each !== id)
  if (shown) ids.push(id)

  if (ids.length > 0) control.setAttribute("aria-describedby", ids.join(" "))
  else control.removeAttribute("aria-describedby")
}
