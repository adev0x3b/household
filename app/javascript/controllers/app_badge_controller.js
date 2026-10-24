import { Controller } from "@hotwired/stimulus"

// The installed app's icon shows the bell's unread count (Badging API),
// following Views::Notifications::Badge, which is replaced live.
export default class extends Controller {
  static values = { count: Number }

  countValueChanged(count) {
    if (!("setAppBadge" in navigator)) return

    const update = count > 0 ? navigator.setAppBadge(count) : navigator.clearAppBadge()
    update.catch(() => {})
  }
}
