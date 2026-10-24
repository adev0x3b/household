import { Controller } from "@hotwired/stimulus"

// A finger that has moved this far (px) has shown which way it is going.
const AXIS_LOCK = 8
// Swiped past this share of the toast's width, it is flung off; short of it, it slides back.
const FLING_FRACTION = 0.35

// One toast (Components::Toast): it goes away by itself after its duration,
// unless it is one that stays until closed, waits while the pointer is over
// it or the focus is in it, and on a touch screen can be swiped away
// sideways.
export default class extends Controller {
  static targets = ["progress"]
  static values = { duration: { type: Number, default: 5000 }, untilClosed: Boolean }

  connect() {
    this.remaining = this.durationValue
    this.running = false
    this.swiping = false
    // Stated as not passive: #swipeMove calls preventDefault() to keep the
    // page from scrolling under the finger, and a passive listener's
    // preventDefault() is ignored without a word.
    this.element.addEventListener("touchstart", this.#swipeStart, { passive: false })
    this.element.addEventListener("touchmove", this.#swipeMove, { passive: false })
    this.element.addEventListener("touchend", this.#swipeEnd, { passive: false })
    this.startTimer()
  }

  disconnect() {
    this.cleanup()
  }

  startTimer() {
    if (this.untilClosedValue || this.running) return

    this.running = true
    this.startedAt = Date.now()
    this.animateProgress()
    this.timeout = setTimeout(() => this.close(), this.remaining)
  }

  // The pointer and the focus can both hold the toast, and the second to
  // arrive must not count the time already counted.
  pauseTimer() {
    if (!this.running) return

    this.running = false
    const elapsed = Date.now() - this.startedAt
    this.remaining = Math.max(0, this.remaining - elapsed)
    clearTimeout(this.timeout)
    cancelAnimationFrame(this.frame)
  }

  // Only once neither holds it: the pointer leaving a toast whose close
  // button has the focus leaves it waiting, and so does the focus leaving
  // one the pointer rests on.
  resumeTimer(event) {
    if (this.swiping || this.#held(event)) return

    this.startTimer()
  }

  #held(event) {
    const focused = event?.type === "focusout" ? event.relatedTarget : document.activeElement
    if (focused instanceof Node && this.element.contains(focused)) return true

    return event?.type !== "mouseleave" && this.element.matches(":hover")
  }

  animateProgress() {
    const tick = () => {
      const elapsed = Date.now() - this.startedAt
      const left = Math.max(0, this.remaining - elapsed)
      const percent = (left / this.durationValue) * 100
      this.progressTarget.value = percent
      if (percent > 0) this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }

  // Listened for with options Stimulus actions can't state, which is why
  // they are kept as fields: removing a listener needs the same function.
  #swipeStart = (event) => {
    if (event.touches.length !== 1) return

    this.swiping = true
    this.origin = { x: event.touches[0].clientX, y: event.touches[0].clientY }
    this.deltaX = 0
    this.locked = false
    this.pauseTimer()
    // The slide-in animation fills forwards, and a running animation wins
    // over inline transform and opacity; it is taken off so the finger's
    // position shows.
    this.element.style.animation = "none"
    this.element.style.transition = "none"
  }

  #swipeMove = (event) => {
    if (!this.swiping) return

    const dx = event.touches[0].clientX - this.origin.x
    const dy = event.touches[0].clientY - this.origin.y
    if (!this.locked) {
      if (Math.abs(dx) > AXIS_LOCK || Math.abs(dy) > AXIS_LOCK) {
        this.locked = true
        this.horizontal = Math.abs(dx) >= Math.abs(dy)
      }
      return
    }
    // A mostly vertical gesture is the page scrolling, not a swipe.
    if (!this.horizontal) {
      this.swipeReset()
      return
    }

    event.preventDefault()
    this.deltaX = dx
    this.element.style.transform = `translateX(${dx}px)`
    this.element.style.opacity = Math.max(0, 1 - Math.abs(dx) / this.element.offsetWidth)
  }

  #swipeEnd = () => {
    if (!this.swiping) return

    if (Math.abs(this.deltaX) > this.element.offsetWidth * FLING_FRACTION) this.fling()
    else this.swipeReset()
  }

  fling() {
    const direction = this.deltaX > 0 ? 1 : -1
    this.element.style.transition = "transform 0.2s ease-out, opacity 0.2s ease-out"
    this.element.style.transform = `translateX(${direction * this.element.offsetWidth}px)`
    this.element.style.opacity = "0"
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
    this.cleanup()
  }

  swipeReset() {
    this.swiping = false
    this.element.style.transition = "transform 0.2s ease, opacity 0.2s ease"
    this.element.style.transform = ""
    this.element.style.opacity = ""
    this.element.style.animation = ""
    this.resumeTimer()
  }

  close() {
    this.cleanup()
    // The leaving animation is a class; an inline "none" left from a swipe would stop it.
    this.element.style.animation = ""
    this.element.classList.add("is-removing")
    this.element.addEventListener("animationend", () => this.element.remove(), { once: true })
  }

  cleanup() {
    clearTimeout(this.timeout)
    cancelAnimationFrame(this.frame)
    this.element.removeEventListener("touchstart", this.#swipeStart)
    this.element.removeEventListener("touchmove", this.#swipeMove)
    this.element.removeEventListener("touchend", this.#swipeEnd)
  }
}
