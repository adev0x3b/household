import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "helpers/csrf"

// Tells the server this browser's time zone when it isn't the one saved on
// the profile (TimeZonesController), so reminders fire on the person's clock.
export default class extends Controller {
  static values = { current: String, url: String }

  connect() {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!zone || zone === this.currentValue) return

    this.currentValue = zone
    fetch(this.urlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify({ time_zone: zone })
    }).catch(() => {})
  }
}
