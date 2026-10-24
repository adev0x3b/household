# frozen_string_literal: true

# Series deleted in bulk with everything that hangs off them, in the order
# the foreign keys allow and with no callbacks: their days and what hangs
# off those (Occurrence.delete_with_children), their details rows (the
# lists on them go by cascade), shares and reminders, then the series —
# their slots and exclusions by cascade. A cost about one of them goes on,
# unattached; a request about one, without it. What a kind gives back when
# its days go (Event#on_occurrences_destroying) is the caller's, first.
#
#   Events::Purge.call(Event.where(profile_id: ids))   # a relation (Profiles::Destroy)
#   Events::Purge.call(events)                         # or records (Occurrences::Destroy, several at once)
module Events
  class Purge
    def self.call(events) = new(events).call

    def initialize(events)
      @ids = events.is_a?(ActiveRecord::Relation) ? events.reselect(:id) : events.map(&:id)
    end

    def call
      return if @ids.is_a?(Array) && @ids.empty?

      Transaction::Details.where(about_type: "Event", about_id: @ids).update_all(about_type: nil, about_id: nil)
      Occurrence.delete_with_children(Occurrence.where(event_id: @ids))
      Event.types.each { |kind| kind.details_class.where(event_id: @ids).delete_all }
      EventShare.where(event_id: @ids).delete_all
      reminders = EventReminder.where(event_id: @ids)
      EventReminderDelivery.where(event_reminder_id: reminders.select(:id)).delete_all
      reminders.delete_all
      Event.where(id: @ids).delete_all
    end
  end
end
