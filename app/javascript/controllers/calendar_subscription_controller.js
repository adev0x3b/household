import { Controller } from "@hotwired/stimulus"
import { subscribeToCalendar } from "channels/calendar_channel"

// The calendar's subscription to its month's live updates, held while the
// calendar is on the page. Moving to another month is a page refresh that
// morphs the element in place, so only its values change: a changed year
// or month resubscribes, where connect() alone would leave it listening to
// the old month. Each update it applies is announced as
// "calendar-subscription:changed", for the page around it (home).
export default class extends Controller {
  static values = { profileId: Number, year: Number, month: Number }

  connect() {
    this.subscribe()
  }

  disconnect() {
    this.unsubscribe()
  }

  profileIdValueChanged() {
    this.resubscribe()
  }
  yearValueChanged() {
    this.resubscribe()
  }
  monthValueChanged() {
    this.resubscribe()
  }

  // Value callbacks also fire while Stimulus initializes the element, before
  // connect(): only a connected element (re)subscribes.
  resubscribe() {
    if (!this.element.isConnected || !this.subscription) return
    this.unsubscribe()
    this.subscribe()
  }

  subscribe() {
    if (!this.profileIdValue || !this.yearValue || !this.monthValue) return
    this.subscription = subscribeToCalendar(this.profileIdValue, this.yearValue, this.monthValue, () =>
      this.dispatch("changed")
    )
  }

  unsubscribe() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }
}
