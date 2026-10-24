import { Controller } from "@hotwired/stimulus"

// Copies a field's text (an invitation link, a file's link) with the
// button beside it, which says "Copied" for a moment.
export default class extends Controller {
  static targets = ["source", "button"]
  static values = { copied: String }

  select() {
    this.sourceTarget.select()
  }

  async copy() {
    this.sourceTarget.select()
    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
    } catch {
      // The clipboard API needs a secure context, which plain http is not.
      document.execCommand("copy")
    }
    this.confirm()
  }

  confirm() {
    const button = this.buttonTarget
    const label = button.title
    const icon = button.querySelector("i")

    button.title = this.copiedValue
    button.setAttribute("aria-label", this.copiedValue)
    icon?.classList.replace("fa-copy", "fa-check")
    setTimeout(() => {
      button.title = label
      button.setAttribute("aria-label", label)
      icon?.classList.replace("fa-check", "fa-copy")
    }, 2000)
  }
}
