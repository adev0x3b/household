import { Controller } from "@hotwired/stimulus"

// Shows or hides what was typed in a password field (Components::PasswordField).
// The button is a toggle: "Show password", pressed or not, its eye crossed out
// while the password shows.
export default class extends Controller {
  static targets = ["input", "button", "icon"]

  toggle() {
    const showing = this.inputTarget.type === "password"
    this.inputTarget.type = showing ? "text" : "password"
    this.buttonTarget.setAttribute("aria-pressed", String(showing))
    this.iconTarget.classList.toggle("fa-eye", !showing)
    this.iconTarget.classList.toggle("fa-eye-slash", showing)
  }
}
