import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// A request of Turbo's that got no answer the app could word: no connection,
// a crash, or a part of the page that didn't come. Each is told with a toast
// where the person stands (Components::Toasts), and the page, an open modal
// and what was typed stay as they were.
export default class extends Controller {
  static targets = ["offline", "serverError", "missing"]

  // Turbo only logs a press or a frame that got no answer, and the person
  // would see nothing happen. A visit it would load as a whole page, which
  // offline is the service worker's offline page instead of the page the
  // person was on, so that one is held back.
  unanswered(event) {
    if (isPrefetch(event) || isBack(event)) return

    if (isVisit(event)) {
      event.preventDefault()
      endVisit()
    }
    this.#show(this.offlineTarget)
  }

  // Left to Turbo, the error page would be drawn over the page, without its
  // styles, which the page's Content Security Policy refuses. Only a 5xx is
  // held back: a 4xx is an answer the app worded (the sign-in page comes
  // back as a 422), and Turbo draws it.
  answered(event) {
    if (isPrefetch(event) || !event.detail.fetchResponse.serverError) return

    event.preventDefault()
    if (isBack(event)) {
      window.location.reload()
      return
    }

    if (isVisit(event)) endVisit()
    this.#show(this.serverErrorTarget)
  }

  // A frame whose answer doesn't hold it keeps what it showed, rather than
  // show Turbo's "Content missing", in English.
  frameMissing(event) {
    event.preventDefault()
    this.#show(this.missingTarget)
  }

  #show(template) {
    this.element.append(template.content.firstElementChild.cloneNode(true))
  }
}

// Turbo fetches a link the pointer rests on before it is pressed; the person
// has asked for nothing yet, so a failure there is not theirs to hear about.
function isPrefetch(event) {
  return event.target instanceof HTMLAnchorElement
}

// A visit's request has no element of its own, so its events come from the
// document's element.
function isVisit(event) {
  return event.target === document.documentElement
}

// Back has already put the other page's address in the address bar, so the
// page it left can't stay. The address is loaded whole instead, as if opened
// directly, and the browser shows its answer: the offline page, Turbo's own
// choice, or the public error page.
function isBack(event) {
  return isVisit(event) && Turbo.navigator.currentVisit?.action === "restore"
}

// Nothing ends a visit whose answer was held back. Failing it is what Turbo
// itself does after drawing an error page: the progress bar and the page's
// busy state go, and the page stays as it is.
function endVisit() {
  Turbo.navigator.currentVisit?.fail()
}
