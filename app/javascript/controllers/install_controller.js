import { Controller } from "@hotwired/stimulus"
import { INSTALLABLE_EVENT, pendingInstallPrompt, forgetInstallPrompt, isStandalone, isIos } from "pwa"

// "Install the app" in the navbar's "This device"
// (Views::Layouts::DeviceSettings). Chromium offers installing
// (beforeinstallprompt, kept by pwa.js): the button shows it. iOS has no such
// offer: a hint says how (Share → Add to Home Screen). Already installed:
// neither.
export default class extends Controller {
  static targets = ["button", "iosHint"]

  connect() {
    window.addEventListener(INSTALLABLE_EVENT, this.#refresh)
    window.addEventListener("appinstalled", this.#refresh)
    this.#refresh()
  }

  disconnect() {
    window.removeEventListener(INSTALLABLE_EVENT, this.#refresh)
    window.removeEventListener("appinstalled", this.#refresh)
  }

  async install() {
    const prompt = pendingInstallPrompt()
    if (!prompt) return

    prompt.prompt()
    await prompt.userChoice
    forgetInstallPrompt()
    this.#refresh()
  }

  // Listened for on the window, which is why it is kept as a field:
  // removing a listener needs the same function.
  #refresh = () => {
    const installed = isStandalone()
    this.buttonTarget.hidden = installed || !pendingInstallPrompt()
    this.iosHintTarget.hidden = installed || !isIos()
  }
}
