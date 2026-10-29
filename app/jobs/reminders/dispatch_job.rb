# frozen_string_literal: true

module Reminders
  # Sends the reminders that have come due (config/recurring.yml, every few
  # minutes): for each reminder, each day still to do whose time minus the
  # reminder's offset has passed, a `reminder_due` notification to its
  # person (the bell, and the devices they turned push on for), and a mail
  # when they asked for the reminder by email (Emails::Kinds::Reminder).
  #
  # Late is better than never, but never after the fact: a reminder whose
  # time passed while the app was down still goes out as long as the thing
  # isn't due yet. One set after its time had already passed doesn't fire.
  # Each reminder fires once per slot (EventReminderDelivery) — per dose,
  # for a medication taken several times a day. A series whose reminders
  # fail is reported and passed over, so the others still go out.
  class DispatchJob < ApplicationJob
    runs_outside_web_server

    # Deliveries are only looked up for upcoming days; older ones go.
    KEEP_DELIVERIES = 60.days

    def perform
      now = Time.current
      window = (now.to_date - 1)..(now.to_date + EventReminder::MAX_OFFSET.minutes.in_days.ceil + 1)

      events = Event.where(id: EventReminder.select(:event_id)).visible_in(window.first, window.last)
      events.includes(event_reminders: :profile).find_in_batches do |batch|
        Event.preload_occurrences(batch, window.first, window.last)
        readable = readable_by_their_people(batch)
        batch.each { |event| on_its_own(event) { dispatch(event, window, now, readable) } }
      end

      EventReminderDelivery.where(created_at: ...KEEP_DELIVERIES.ago).delete_all
    end

    private

    def dispatch(event, window, now, readable)
      occurrences = event.occurrences_between(window.first, window.last)
      return if occurrences.empty?

      event.event_reminders.each do |reminder|
        next unless readable.include?([ reminder.profile_id, event.id ])

        occurrences.each do |occurrence|
          next unless occurrence.open?

          due_at, timed = DueAt.for(occurrence, reminder.profile.zone)
          fire_at = due_at - reminder.offset
          next unless fire_at <= now && due_at > now && fire_at >= reminder.created_at

          deliver(reminder, event, occurrence, due_at, timed)
        end
      end
    end

    # The [person, series] pairs of a batch whose person may still read the
    # series, asked once per person with a reminder in it. Unshared since
    # they set it, or no longer in the household: no reminder.
    def readable_by_their_people(batch)
      people = batch.flat_map(&:event_reminders).map(&:profile).uniq
      people.each_with_object(Set.new) do |profile, readable|
        Event.accessible_by(profile).where(id: batch).pluck(:id).each { |id| readable << [ profile.id, id ] }
      end
    end

    # The claim, the notification and the mail are saved together: a run
    # that fails between them leaves the reminder unclaimed, for the next run
    # to send.
    def deliver(reminder, event, occurrence, due_at, timed)
      EventReminderDelivery.transaction do
        claimed = EventReminderDelivery.insert(
          { event_reminder_id: reminder.id, date: occurrence.date, time: occurrence.time, created_at: Time.current },
          unique_by: %i[event_reminder_id date time], returning: :id
        )
        if claimed.rows.any?
          Notifications::Deliver.call(
            recipient: reminder.profile, kind: :reminder_due, subject: event, title: occurrence.event_label,
            data: { date: occurrence.date.iso8601, due_at: due_at.iso8601, timed: timed, time: occurrence.time_string, anchor: occurrence.anchor }.compact
          )
          mail(reminder, occurrence, due_at) if reminder.by_email? && Emails.for_reminders(reminder.profile) == :available
        end
      end
    end

    # Worth sending until the thing is due; what it says is made as it goes,
    # from the day as it is then.
    def mail(reminder, occurrence, due_at)
      data = { "event_reminder_id" => reminder.id, "date" => occurrence.date.iso8601, "time" => occurrence.time_string }.compact
      Emails::Enqueue.call(reminder.profile, :reminder, data: data, latest: due_at)
    end
  end
end
