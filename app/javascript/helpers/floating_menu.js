// A menu drawn once on a page and opened against whichever of many buttons
// was pressed: a calendar card's "more", a day's "+" or a message's smile.
// Drawn once, it can't sit beside each button in the page's flow, so it
// floats, fixed to the window next to the button that opened it. It closes
// on a click elsewhere, on Escape, when focus leaves it, and when a scroll
// moves its button or the window changes size, since it would no longer sit
// by its button. The controller that owns it fills it for the button before
// opening it.
export class FloatingMenu {
  #menu
  #side
  #opener = null
  #openedAt = null
  #anchor = null
  #align = "end"

  #closeOutside = (event) => {
    if (!this.#menu.contains(event.target) && !this.#opener?.contains(event.target)) this.close()
  }

  #closeOnEscape = (event) => {
    if (event.key === "Escape") this.close({ returnFocus: true })
  }

  #closeOnFocusOut = (event) => {
    const next = event.relatedTarget
    if (next && !this.#menu.contains(next) && !this.#opener?.contains(next)) this.close()
  }

  // A scroll that leaves the button where it was keeps the menu: a script
  // that scrolls to look at something and back (an accessibility checker,
  // a page refresh keeping its place) has not moved anything the reader
  // sees.
  #closeOnScroll = () => {
    const { top, left } = this.#opener.getBoundingClientRect()
    if (top !== this.#openedAt.top || left !== this.#openedAt.left) this.close()
  }

  #closeOnResize = () => this.close()

  // side: where the menu opens when there is room, "below" its button or
  // "above" it; the other side when there isn't.
  constructor(menu, { side = "below" } = {}) {
    this.#menu = menu
    this.#side = side
  }

  get isOpen() {
    return this.#opener !== null
  }

  // Whether the menu is open from this button, so a second press closes it.
  isOpenFrom(opener) {
    return this.#opener === opener
  }

  // align: "end" lines the menu's right edge up with the button's, "start"
  // its left edge. anchor: what it opens beside, when that is more than the
  // button (a message's picker opens over the whole message).
  openAt(opener, { align = "end", anchor = opener } = {}) {
    if (this.isOpen) this.close()

    this.#opener = opener
    this.#anchor = anchor
    this.#align = align
    this.#menu.classList.add("is-open")
    this.#place()
    const { top, left } = opener.getBoundingClientRect()
    this.#openedAt = { top, left }
    opener.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.#closeOutside, true)
    document.addEventListener("keydown", this.#closeOnEscape)
    document.addEventListener("scroll", this.#closeOnScroll, true)
    window.addEventListener("resize", this.#closeOnResize)
    this.#menu.addEventListener("focusout", this.#closeOnFocusOut)
    this.#firstEntry()?.focus({ preventScroll: true })
  }

  // returnFocus: hand focus back to the button, as after Escape or a choice,
  // so a keyboard reader carries on from where they were.
  close({ returnFocus = false } = {}) {
    const opener = this.#opener
    if (!opener) return

    this.#opener = null
    this.#anchor = null
    this.#menu.classList.remove("is-open")
    opener.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.#closeOutside, true)
    document.removeEventListener("keydown", this.#closeOnEscape)
    document.removeEventListener("scroll", this.#closeOnScroll, true)
    window.removeEventListener("resize", this.#closeOnResize)
    this.#menu.removeEventListener("focusout", this.#closeOnFocusOut)
    if (returnFocus && opener.isConnected) opener.focus({ preventScroll: true })
  }

  // On the preferred side first, then on the other when an edge of the menu
  // would be hidden there: past the window, or under the top bar or the
  // phone's bottom bar, which a position alone can't tell. Where neither
  // side shows it whole, the preferred one.
  #place() {
    const anchor = this.#anchor.getBoundingClientRect()
    const size = this.#menu.getBoundingClientRect()
    const viewport = { width: document.documentElement.clientWidth, height: window.innerHeight }
    const sides = this.#side === "below" ? ["below", "above"] : ["above", "below"]
    const moveTo = (side) => {
      const { top, left } = placement(anchor, size, viewport, { side, align: this.#align })
      this.#menu.style.top = `${top}px`
      this.#menu.style.left = `${left}px`
    }

    for (const side of sides) {
      moveTo(side)
      if (this.#shown()) return
    }
    moveTo(this.#side)
  }

  #shown() {
    const box = this.#menu.getBoundingClientRect()
    const x = box.left + box.width / 2

    return [box.top + 1, box.bottom - 1].every(
      (y) => y >= 0 && y <= window.innerHeight && this.#menu.contains(document.elementFromPoint(x, y))
    )
  }

  #firstEntry() {
    return [...this.#menu.querySelectorAll("a[href], button")].find((entry) => !entry.hidden)
  }
}

// Where a menu of `size` goes beside a button whose box is `anchor`, in a
// window of `viewport`: a small gap from the button, on `side`, its edge on
// the button's (`align`), and never past the window's left or right edge.
export function placement(anchor, size, viewport, { side, align, gap = 4, margin = 8 }) {
  const top = side === "below" ? anchor.bottom + gap : anchor.top - gap - size.height
  const left = align === "end" ? anchor.right - size.width : anchor.left
  const widest = Math.max(margin, viewport.width - size.width - margin)

  return { top, left: Math.min(Math.max(left, margin), widest) }
}
