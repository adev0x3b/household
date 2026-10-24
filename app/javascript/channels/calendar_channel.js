import consumer from "channels/consumer"
import { Turbo } from "@hotwired/turbo-rails"

// The calendar's live updates: a subscription to one profile's month, whose
// messages are Turbo Streams the server broadcasts when a day changes.
// `changed` is told after each one is applied, for a page that keeps more
// than its day cards in step with the calendar.
export function subscribeToCalendar(profileId, year, month, changed = () => {}) {
  const room = `profile_${profileId}:${year}-${String(month).padStart(2, "0")}`
  return consumer.subscriptions.create(
    { channel: "CalendarChannel", room },
    {
      received(stream) {
        Turbo.renderStreamMessage(stream)
        changed()
      }
    }
  )
}
