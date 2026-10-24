import { Controller } from "@hotwired/stimulus"

// A <details> that keeps the open/closed state its reader picked when the
// frame around it is re-rendered (frame-poll reloads it every few seconds,
// and the server only knows the default). Only clicks are remembered, never
// the server's default, so a section that starts failing still opens itself.
// Per tab (sessionStorage), under the key the server gives.
export default class extends Controller {
  static values = { key: String }

  connect() {
    const saved = this.read()
    if (saved !== null) this.element.open = saved === "open"
  }

  // The summary's click comes before the browser flips the details: save
  // the state it's about to take.
  remember() {
    try {
      sessionStorage.setItem(this.storageKey, this.element.open ? "closed" : "open")
    } catch {
      // storage unavailable (private mode): the default stands
    }
  }

  read() {
    try {
      return sessionStorage.getItem(this.storageKey)
    } catch {
      return null
    }
  }

  get storageKey() {
    return `disclosure:${this.keyValue}`
  }
}
