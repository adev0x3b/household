// Puts the focus somewhere sensible when the page redraws the element that
// held it: a stream or a broadcast that replaces a day card, a page refresh
// that morphs a list. The browser leaves a focus whose element was taken
// away on the page's body, and a keyboard reader would start again from the
// top bar.
//
// Turbo already gives the focus to an element drawn again under the same
// id, so whatever must keep the focus through a redraw has an id that stays
// the same. What Turbo can't know is where the focus goes when the element
// doesn't come back (a row settled off a list): it names that itself, in
// order, with data-focus-fallback="next-id previous-id". Failing those, a
// focus that was in the page's content goes to the content, so the next Tab
// still goes on from there.
//
// Turbo also switches a form's button off while the form is sent, and a
// button switched off drops the focus to the body. A button that stays on
// the page takes it back once the answer is in.
export class FocusKeeper {
  #page
  #content
  #held = null
  #inContent = false
  #observer = null

  // page: the body, whose every change is watched. A visit to another page
  // draws a new one, so the reader starts that page at its top even where
  // it has an id the old one had. content: a function answering the page's
  // content element, read each time, since a page refresh may draw a new one.
  constructor(page, { content = () => null } = {}) {
    this.#page = page
    this.#content = content
  }

  start() {
    this.#page.addEventListener("focusin", this.#remember)
    this.#page.addEventListener("turbo:submit-end", this.#sent)
    this.#observer = new MutationObserver(this.#redrawn)
    this.#observer.observe(this.#page, { childList: true, subtree: true })
  }

  stop() {
    this.#page.removeEventListener("focusin", this.#remember)
    this.#page.removeEventListener("turbo:submit-end", this.#sent)
    this.#observer?.disconnect()
    this.#forget()
  }

  // The element itself is kept, not its id: it still carries its id and its
  // fallbacks once it has been taken off the page.
  #remember = (event) => {
    this.#held = event.target
    this.#inContent = this.#content()?.contains(event.target) ?? false
  }

  // Told after every change to the page, once the change is whole: a stream
  // or a morph takes the old element away and puts the new one in within
  // the same task. A focus the reader moved elsewhere is theirs.
  #redrawn = () => {
    if (!this.#held || this.#held.isConnected || this.#movedOn) return

    const next = replacementFor(this.#held, this.#page.ownerDocument) ?? (this.#inContent ? this.#content() : null)
    this.#forget()
    next?.focus({ preventScroll: true })
  }

  // Turbo has switched the button back on by now. One drawn again or gone
  // is the mutation's to follow.
  #sent = (event) => {
    const button = event.detail?.formSubmission?.submitter
    if (!button || button !== this.#held || !button.isConnected || this.#movedOn) return

    button.focus({ preventScroll: true })
  }

  get #movedOn() {
    const { activeElement, body } = this.#page.ownerDocument
    return Boolean(activeElement) && activeElement !== body
  }

  #forget() {
    this.#held = null
    this.#inContent = false
  }
}

// The element that takes the focus of one taken off the page: the one now
// under its id, else the first of its fallbacks that can be focused.
export function replacementFor(element, document) {
  const ids = [element.id, ...(element.dataset?.focusFallback ?? "").split(/\s+/)].filter(Boolean)

  return ids.map((id) => document.getElementById(id)).find((candidate) => candidate && focusable(candidate))
}

// Shown, not folded away or behind an open modal, and not switched off.
function focusable(element) {
  if (element.closest("[inert], [hidden]") || element.disabled) return false

  return element.checkVisibility?.() ?? true
}
