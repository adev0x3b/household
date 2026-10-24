import { Controller } from "@hotwired/stimulus"

// The parameter that names a field typed in.
const TYPED = "typed_fields[]"

// The form of something housemates edit together (Components::Form) sends,
// with its fields, the names of those changed since it was drawn. When
// someone saved the record meanwhile, the form comes back with what was
// typed in these and what they saved in the rest (EditedTogether#edit_as).
// A form shown again carries the names typed before it was, which still
// count.
export default class extends Controller {
  connect() {
    this.drawn = this.values()
    this.typedBefore = this.typedInputs()
      .map((input) => input.value)
      .filter((name) => name !== "")
  }

  note(event) {
    if (event.defaultPrevented) return

    const now = this.values()
    const typed = new Set(this.typedBefore)
    new Set([...this.drawn.keys(), ...now.keys()]).forEach((name) => {
      if (!sameValues(this.drawn.get(name), now.get(name))) typed.add(name)
    })

    // An empty name goes first, so that a form with nothing typed in it
    // still says so: a list that never arrives means the form didn't say.
    this.typedInputs().forEach((input) => input.remove())
    for (const name of ["", ...typed]) this.element.append(hidden(name))
  }

  // What the form would send, by field name: a name can carry several
  // values (a check box and the hidden field before it, a list of choices).
  values() {
    const values = new Map()
    for (const [name, value] of new FormData(this.element)) {
      if (name === TYPED) continue

      values.set(name, [...(values.get(name) ?? []), value instanceof File ? value.name : value])
    }
    return values
  }

  typedInputs() {
    return Array.from(this.element.querySelectorAll(`input[name="${TYPED}"]`))
  }
}

function sameValues(drawn = [], now = []) {
  return drawn.length === now.length && drawn.every((value, index) => value === now[index])
}

function hidden(name) {
  const input = document.createElement("input")
  input.type = "hidden"
  input.name = TYPED
  input.value = name
  return input
}
