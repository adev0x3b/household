import { Controller } from "@hotwired/stimulus"

// The eval scenario editor (Views::Assistant::Evals::Scenarios::Form):
// adds and removes message / check rows from their <template>s, and shows
// the picked check's argument help and example.
export default class extends Controller {
  static targets = ["messages", "messageTemplate", "expects", "expectTemplate"]

  addMessage() {
    this.messagesTarget.insertAdjacentHTML("beforeend", this.messageTemplateTarget.innerHTML)
    this.messagesTarget.lastElementChild?.querySelector("textarea")?.focus()
  }

  addExpect() {
    this.expectsTarget.insertAdjacentHTML("beforeend", this.expectTemplateTarget.innerHTML)
    this.expectsTarget.lastElementChild?.querySelector("select")?.focus()
  }

  remove(event) {
    event.currentTarget.closest("[data-row]")?.remove()
  }

  describe(event) {
    const option = event.currentTarget.selectedOptions[0]
    const row = event.currentTarget.closest("[data-row]")
    if (!option || !row) return

    const help = row.querySelector("[data-check-help]")
    if (help) help.textContent = option.dataset.help || ""
    const argument = row.querySelector("textarea")
    if (argument) argument.placeholder = option.dataset.example || ""
  }
}
