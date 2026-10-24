import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { ScrollLock } from "helpers/scroll_lock"
import { confirmationFor } from "helpers/confirmation"

// The app's own confirm dialog (Components::ConfirmDialog). Turbo asks it
// instead of the browser's confirm() before a press with data-turbo-confirm,
// and another controller asks it through an outlet, as the uploader does
// before closing.
export default class extends Controller {
  static targets = ["question", "confirm", "dismiss"]
  static values = { words: Object }

  #answer = null
  #press = null
  #scrollLock = new ScrollLock()

  // Heard in the capture phase, before Turbo turns a link into a form of its
  // own, so the link is still known when its question is asked.
  #remember = (event) => {
    this.#press = event.target instanceof Element ? event.target.closest("[data-turbo-confirm]") : null
  }

  #askForTurbo = (question, form, submitter) =>
    this.ask(question, confirmationFor(question, { form, submitter, press: this.#press }))

  connect() {
    document.addEventListener("click", this.#remember, true)
    Turbo.config.forms.confirm = this.#askForTurbo
  }

  disconnect() {
    document.removeEventListener("click", this.#remember, true)
    if (Turbo.config.forms.confirm === this.#askForTurbo) Turbo.config.forms.confirm = undefined
    this.#settle(false)
    this.#scrollLock.release()
  }

  // Resolves to true when the reader confirms. `confirm` is the confirming
  // button's words, `dismiss` the other's, and `danger` sets the first apart
  // as destructive.
  ask(question, { confirm = this.wordsValue.confirm, dismiss = this.wordsValue.dismiss, danger = false } = {}) {
    this.#settle(false)
    this.questionTarget.textContent = question
    this.confirmTarget.textContent = confirm
    this.dismissTarget.textContent = dismiss
    this.confirmTarget.classList.toggle("modal__btn--danger", danger)
    this.confirmTarget.classList.toggle("modal__btn--primary", !danger)
    this.element.returnValue = ""
    if (!this.element.open) this.element.showModal()
    this.#scrollLock.hold()

    return new Promise((resolve) => {
      this.#answer = resolve
    })
  }

  // Either button closes the dialog with its own value; Escape and the
  // backdrop close it with none.
  closed() {
    this.#scrollLock.release()
    this.#settle(this.element.returnValue === "confirm")
  }

  // The dialog has no padding of its own, so a click whose target is the
  // dialog itself landed on its backdrop.
  backdropClick(event) {
    if (event.target === this.element) this.element.close()
  }

  // A page refresh that lands while the question is open would morph the
  // dialog shut under the reader's finger.
  holdWhileOpen(event) {
    if (this.element.open) event.preventDefault()
  }

  #settle(answer) {
    this.#answer?.(answer)
    this.#answer = null
  }
}
