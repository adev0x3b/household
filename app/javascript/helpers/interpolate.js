// Fills the %{name} placeholders of a phrase the server translated, so a
// line a controller completes on the page ("3 min left", "Scanned
// %{isbn}") is worded in the locale files like every other. Every
// occurrence is filled, since a phrase may name a value twice.
export function interpolate(phrase, values) {
  return Object.entries(values).reduce((text, [name, value]) => fill(text, name, value), phrase)
}

// The replacement is given as a function: a string replacement would have
// "$&" and the like in a value (a file's name) read as patterns.
function fill(text, name, value) {
  return text.replaceAll(`%{${name}}`, () => String(value))
}
