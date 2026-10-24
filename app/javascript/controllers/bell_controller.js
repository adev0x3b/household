import { Controller } from "@hotwired/stimulus"

// The bell's list (Views::Notifications::Bell) is read again each time
// the bell opens. It is kept from page to page and only pushed new rows, so
// it would never learn that a notification was read elsewhere, and its
// "5 minutes ago" would never age. The first opening loads it by itself.
export default class extends Controller {
  static targets = ["list"]

  // A list still loading is left to finish. One whose load failed, as when
  // the bell was opened offline, is asked again rather than left loading.
  refresh() {
    if (!this.listTarget.hasAttribute("busy")) this.listTarget.reload()
  }
}
