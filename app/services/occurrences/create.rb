# frozen_string_literal: true

# Saves a new series — a built Event subclass with its series details — on
# the calendar of whoever makes it (`by:`), or on the calendar it was built
# for (a linked housemate's, as their grant allows), authorized with the
# policy of its first day (`create?`), and returns it.
#
#   visit = Appointment.new(title: "Visit", starts_on: date, start_time: "11:00",
#                           details_attributes: { kind: :medical, counterpart: "Moretti" })
#   Occurrences::Create.call(visit, by: current_profile,
#                            recurrence: { frequency: "weekly", week_days: %w[friday], slots: %w[CM CV] },
#                            collection_id: collection.id)
#   visit.first_occurrence  # => the day it starts, to complete! or save
#
# `recurrence[:slots]` lists the times of the day ("08:00" or an anchor such
# as "CV", see Events::TimesOfDay). `collection_id` is re-checked against
# Collection.accessible_by — an inaccessible id is dropped, never trusted.
# Raises ActiveRecord::RecordInvalid when the series is invalid.
# Broadcasting is left to the caller.
module Occurrences
  class Create
    def self.call(event, by:, recurrence: nil, collection_id: nil)
      recurrence = (recurrence || {}).to_h.symbolize_keys.slice(:frequency, :interval, :week_days, :ends, :slots)
      slots = recurrence.delete(:slots)

      event.profile ||= by
      event.rrule = recurrence[:frequency].present? ? Events::RecurrenceRule.build(**recurrence) : nil
      event.assign_slots(slots) if slots.present?
      event.collection_id = accessible_collection_id(by, collection_id) if collection_id.present?
      Pundit.authorize(by, event.first_occurrence, :create?)

      event.save!
      event
    end

    def self.accessible_collection_id(profile, id)
      return nil if id.blank?

      Collection.accessible_by(profile).where(id: id).pick(:id)
    end
  end
end
