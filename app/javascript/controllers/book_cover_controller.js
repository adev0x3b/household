import { Controller } from "@hotwired/stimulus"

// A cover that fails to load gives way to the stand-in drawn under it, so a
// shelf read offline, or a link that has gone, shows titles rather than
// broken images.
export default class extends Controller {
  static targets = ["image"]

  // An image that failed before the controller connected fires no error for it.
  connect() {
    if (this.imageTarget.complete && this.imageTarget.naturalWidth === 0) this.fail()
  }

  fail() {
    this.imageTarget.remove()
  }
}
