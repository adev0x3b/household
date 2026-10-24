import { Controller } from "@hotwired/stimulus"
import { FocusKeeper } from "helpers/focus_keeper"

// Keeps the keyboard focus through live changes (the layout's body): a
// press whose answer, a broadcast or a page refresh redraws the element
// that held it gives the focus to its replacement. The content target is
// the page's own content, where a focus with nowhere else to go lands.
export default class extends Controller {
  static targets = ["content"]

  #keeper = new FocusKeeper(this.element, { content: () => (this.hasContentTarget ? this.contentTarget : null) })

  connect() {
    this.#keeper.start()
  }

  disconnect() {
    this.#keeper.stop()
  }
}
