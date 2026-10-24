import { Controller } from "@hotwired/stimulus"
import { ScrollLock } from "helpers/scroll_lock"

// Pulling the handle: past this share of the sheet's height it closes…
const CLOSE_FRACTION = 0.25
// …or sooner when flicked: this fast (px per ms), having travelled at least this far (px)
const FLICK_VELOCITY = 0.5
const FLICK_MIN = 24

// The navigation drawer (Views::Layouts::Navbar): a bottom sheet on a phone,
// opened by the bottom bar's Menu tab, a side panel from a tablet up,
// opened by the top bar's burger. Closed, the drawer is inert, since it is
// only moved out of sight. Open, everything else is (the page, both bars
// and the skip link), so the focus stays in the drawer; closing gives the
// focus back to whatever opened it. On a phone the sheet's handle is
// pulled down to close it.
export default class extends Controller {
  static targets = ["toggler", "menu", "overlay", "behind", "handle"]

  #scrollLock = new ScrollLock()
  #opener = null
  #drag = null
  #sheetMedia = null

  // Across the tablet width the drawer changes shape and the button that
  // opened it is gone, so a window resized past it closes the drawer.
  #reshaped = () => {
    this.hideMenu()
  }

  connect() {
    document.addEventListener("keydown", this.#closeOnEscape)
    this.#sheetMedia = window.matchMedia(this.#sheetQuery)
    this.#sheetMedia.addEventListener("change", this.#reshaped)
  }

  disconnect() {
    document.removeEventListener("keydown", this.#closeOnEscape)
    this.#sheetMedia?.removeEventListener("change", this.#reshaped)
    this.#stopDrag()
    this.#release()
  }

  toggle(event) {
    this.#opener = event?.currentTarget
    this.isOpen ? this.hideMenu() : this.showMenu()
  }

  showMenu() {
    this.menuTarget.classList.add("is-open")
    this.overlayTarget.classList.add("is-visible")
    this.togglerTargets.forEach((toggler) => {
      toggler.classList.add("is-active")
      toggler.setAttribute("aria-expanded", "true")
    })
    this.behindTargets.forEach((behind) => {
      behind.inert = true
    })
    this.menuTarget.inert = false
    this.#scrollLock.hold()
    this.#firstLink?.focus({ preventScroll: true })
  }

  hideMenu() {
    const wasOpen = this.isOpen
    this.#stopDrag()
    this.menuTarget.classList.remove("is-open")
    this.overlayTarget.classList.remove("is-visible")
    this.togglerTargets.forEach((toggler) => {
      toggler.classList.remove("is-active")
      toggler.setAttribute("aria-expanded", "false")
    })
    this.menuTarget.inert = true
    this.#release()
    if (wasOpen) this.#opener?.focus({ preventScroll: true })
    this.#opener = null
  }

  get isOpen() {
    return this.menuTarget.classList.contains("is-open")
  }

  // The drawer is a bottom sheet below the tablet width the stylesheet
  // names, and stops 0.02px short of it as the stylesheet's own until() does.
  get isSheet() {
    return window.matchMedia(this.#sheetQuery).matches
  }

  // The first link the drawer shows: the wordmark heads the panel, but a
  // phone's sheet hides it, and starts at Home.
  get #firstLink() {
    return [...this.menuTarget.querySelectorAll("a[href], button")].find((link) => link.getClientRects().length > 0)
  }

  get #sheetQuery() {
    const tablet = getComputedStyle(document.documentElement).getPropertyValue("--breakpoint-tablet")
    return `(max-width: ${parseFloat(tablet) - 0.02}px)`
  }

  // The sheet follows the finger through Pointer Events: the handle has
  // touch-action: none, so the browser never takes the gesture for a scroll.
  dragStart(event) {
    if (!this.isOpen || !event.isPrimary || !this.isSheet) return

    this.#drag = { pointerId: event.pointerId, startY: event.clientY, startedAt: event.timeStamp, dy: 0 }
    this.handleTarget.setPointerCapture(event.pointerId)
    this.handleTarget.addEventListener("pointermove", this.#dragMove)
    this.handleTarget.addEventListener("pointerup", this.#dragEnd)
    this.handleTarget.addEventListener("pointercancel", this.#dragEnd)
    this.menuTarget.classList.add("is-dragging")
  }

  // Never above its resting place.
  #dragMove = (event) => {
    if (event.pointerId !== this.#drag?.pointerId) return

    this.#drag.dy = Math.max(0, event.clientY - this.#drag.startY)
    this.menuTarget.style.transform = `translateY(${this.#drag.dy}px)`
  }

  // Let go: far or fast enough closes, anything else snaps back. Both run
  // on the sheet's own transition from where the finger left it, since the
  // inline transform is cleared in the same frame as the class change.
  #dragEnd = (event) => {
    if (event.pointerId !== this.#drag?.pointerId) return

    const { dy, startedAt } = this.#drag
    const elapsed = Math.max(1, event.timeStamp - startedAt)
    const closes =
      dy > this.menuTarget.offsetHeight * CLOSE_FRACTION || (dy > FLICK_MIN && dy / elapsed > FLICK_VELOCITY)
    this.#stopDrag()
    if (closes) this.hideMenu()
  }

  #stopDrag() {
    if (this.#drag) {
      try {
        this.handleTarget.releasePointerCapture(this.#drag.pointerId)
      } catch {
        // The browser released it already, as it does when the pointer is cancelled.
      }
    }
    this.#drag = null
    this.handleTarget.removeEventListener("pointermove", this.#dragMove)
    this.handleTarget.removeEventListener("pointerup", this.#dragEnd)
    this.handleTarget.removeEventListener("pointercancel", this.#dragEnd)
    this.menuTarget.classList.remove("is-dragging")
    this.menuTarget.style.transform = ""
  }

  // The page usable again. Also on disconnect: a visit made from the open
  // drawer must not leave the next page inert.
  #release() {
    this.behindTargets.forEach((behind) => {
      behind.inert = false
    })
    this.#scrollLock.release()
  }

  #closeOnEscape = (event) => {
    if (event.key === "Escape") this.hideMenu()
  }
}
