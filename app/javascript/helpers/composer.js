// The box grows with its text up to this height (px), about six lines, so
// the thread above keeps most of a phone's screen.
const MAX_HEIGHT = 160

// A chat's message box (the assistant's, a conversation's): Enter sends
// and Shift+Enter adds a line, the box grows with what is typed, and it is
// emptied after a send. A phone has no Shift key, so there Enter adds a
// line and the send button sends.
export class Composer {
  constructor(form, input, { touch = onTouchDevice() } = {}) {
    this.form = form
    this.input = input
    this.touch = touch
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing || this.touch) return

    event.preventDefault()
    this.form.requestSubmit()
  }

  // Shrunk first, so a line deleted takes its height with it.
  grow() {
    this.input.style.height = "auto"
    this.input.style.height = `${Math.min(this.input.scrollHeight, MAX_HEIGHT)}px`
  }

  clear() {
    this.input.value = ""
    this.grow()
  }
}

function onTouchDevice() {
  return window.matchMedia("(pointer: coarse)").matches
}
