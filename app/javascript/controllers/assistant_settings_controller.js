import { Controller } from "@hotwired/stimulus"

// The assistant's provider and model (Views::Installation::Assistant), on
// its settings page and in the first setup: picking a provider shows only
// its connection fields and reloads the model list with that provider's
// models, where the page has one.
export default class extends Controller {
  static targets = ["connection", "models"]
  static values = { modelsUrl: String }

  pick(event) {
    const provider = event.target.value
    this.connectionTargets.forEach((group) => {
      group.hidden = group.dataset.provider !== provider
    })
    if (!this.hasModelsTarget) return

    const url = new URL(this.modelsUrlValue, window.location.origin)
    url.searchParams.set("provider", provider)
    this.modelsTarget.src = url.toString()
  }
}
