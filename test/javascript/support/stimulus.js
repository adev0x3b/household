import "./dom.js"
import { Application } from "@hotwired/stimulus"

// A page with one controller on it: `html` is put in the body and
// `Controller` started as `identifier` on the first element that names it.
// Stimulus catches what an action or a callback throws and only logs it, so
// the page keeps it and `stop()` throws it, failing the test it came from.
export async function mount(identifier, Controller, html) {
  document.body.innerHTML = html
  const application = new Application(document.documentElement)
  const errors = []
  application.handleError = (error) => errors.push(error)
  await application.start()
  application.register(identifier, Controller)

  const element = document.querySelector(`[data-controller~="${identifier}"]`)
  return {
    element,
    controller: application.getControllerForElementAndIdentifier(element, identifier),
    stop() {
      application.stop()
      document.body.replaceChildren()
      if (errors.length > 0) throw errors[0]
    }
  }
}

// Stimulus finds the targets and actions of what is added to the page
// through a mutation observer, which runs only once the code adding it has
// finished. A test waits for it before it acts on what it added.
export function settle() {
  return new Promise((resolve) => setTimeout(resolve, 0))
}
