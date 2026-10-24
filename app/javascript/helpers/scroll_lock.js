// Keeps the page from scrolling behind a layer that covers it: a modal, the
// navbar's drawer. Two layers can be open at once (a modal over the
// drawer), so the page is counted held by each and scrolls again only when
// the last of them lets go, not when the first does.
const holders = new WeakMap()

export class ScrollLock {
  constructor(page = document.body) {
    this.page = page
    this.held = false
  }

  hold() {
    if (this.held) return

    this.held = true
    holders.set(this.page, this.count + 1)
    this.page.style.overflow = "hidden"
  }

  release() {
    if (!this.held) return

    this.held = false
    holders.set(this.page, this.count - 1)
    if (this.count === 0) this.page.style.overflow = ""
  }

  get count() {
    return holders.get(this.page) || 0
  }
}
