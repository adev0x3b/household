import { Controller } from "@hotwired/stimulus"
import { FloatingMenu } from "helpers/floating_menu"

// Every message's smile on a conversation's page opens this one picker of
// quick emoji (Views::Conversations::ReactionPicker), over the message
// pressed and sending to it. It opens from the message's own edge, the
// left for theirs and the right for one's own, so it stays on the screen.
export default class extends Controller {
  static targets = ["menu", "form"]

  #menu = null

  connect() {
    this.#menu = new FloatingMenu(this.menuTarget, { side: "above" })
  }

  disconnect() {
    this.#menu.close()
  }

  open({ currentTarget, params: { url, message, align } }) {
    if (this.#menu.isOpenFrom(currentTarget)) return this.#menu.close()

    this.formTarget.action = url
    this.#menu.openAt(currentTarget, { align, anchor: document.getElementById(message) ?? currentTarget })
  }

  chosen() {
    this.#menu.close({ returnFocus: true })
  }

  // A page refresh that lands while the picker is open would morph it
  // back to a form that sends nowhere.
  holdWhileOpen(event) {
    if (this.#menu.isOpen) event.preventDefault()
  }
}
