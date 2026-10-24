import { Controller } from "@hotwired/stimulus"

// Brings its element into view once, as it appears: for an answer drawn
// away from what was pressed (a Try's run, under a long form whose button
// sits in the sticky footer). Only connect() scrolls — what changes inside
// it later (a frame polling) leaves the reader where they are.
export default class extends Controller {
  connect() {
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.scrollIntoView({ block: "center", behavior: still ? "instant" : "smooth" })
  }
}
