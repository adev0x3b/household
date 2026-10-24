# frozen_string_literal: true

module Demo
  # Links between housemates. Alex and Sam linked their calendars early on
  # and each tuned what the other may do: Sam adds meals to Alex's calendar
  # freely, but asks before changing or ticking anything else of Alex's;
  # Alex doesn't see Sam's medications. Over the months Sam asked for a few
  # things — most approved, one declined — and today two requests wait for
  # Alex, as does Robin's wish to link: the bell and the Links button have
  # something to answer.
  #
  # Named Partners, not Links: inside Demo, `Links` would be this part —
  # the app's are always `::Links`.
  class Partners < Part
    def finish
      settle(::Links::Request.call(from: robin, to: alex), read: false)
      upcoming_appointment&.then { |record| ask_to_move(record) }
      upcoming_day("Transaction")&.then { |record| ::Links::Approvals::Hold.call(requester: sam, record: record, kind: :complete) }
    end

    private

    def setup
      at(start + 9) { ::Links::Request.call(from: alex, to: sam) }
      at(start + 10) do
        link = ::Links::Accept.call(Link.between(alex, sam))
        tune(alex, sam, "Meal", create: :on, write: :on)
        tune(sam, alex, "Medication", read: :off)
        tune(sam, alex, "Task", write: :on, delete: :on)
        settle(link)
      end

      [ 45, 90, 130 ].each { |offset| at(start + offset) { asked(:complete, approve: true) } }
      at(start + 70) { asked(:destroy, approve: false) }
    end

    # What `grantor` lets `grantee` do with their `type`s.
    def tune(grantor, grantee, type, **levels)
      LinkGrant.find_by!(grantor: grantor, grantee: grantee, event_type: type).update!(levels.transform_keys { :"#{_1}_level" })
    end

    # Sam asks about one of Alex's past days; Alex answers the next morning.
    def asked(kind, approve:)
      record = past_day("Task", open: kind == :complete) or return
      approval = ::Links::Approvals::Hold.call(requester: sam, record: record, kind: kind)
      at(@now + 1) do
        ::Links::Approvals::Decide.call(approval, approve: approve)
        settle(approval)
      end
    end

    # Sam would like Alex's next visit an hour later: the form's save, held
    # for Alex's OK (a saved day is changed, a projected one saved with it).
    def ask_to_move(record)
      later = (record.start_time || Time.zone.parse("09:00")) + 1.hour
      fields = { start_time: later.strftime("%H:%M") }
      unless record.persisted?
        fields[:event_id] = record.event_id
        fields[:date] = record.date.iso8601
      end
      form = ::Occurrences::FormSave.for("Appointment").new(actor: sam, record: (record if record.persisted?), params: { appointment: fields })
      ::Links::Approvals::Hold.call(requester: sam, record: form.record, kind: :update, payload: form.payload, preview: form.preview)
    end

    # A day of one of Alex's series in the last weeks (still left open).
    def past_day(type, open: true)
      Event.where(profile: alex, type: type).where.not(rrule: nil).order(:starts_on, :id).each do |event|
        event.occurrence_dates_between(@now - 20, @now - 1).reverse_each do |date|
          record = event.occurrence_for(date)
          return record if record.pending? || !open
        end
      end
      nil
    end

    def upcoming_day(type)
      Event.where(profile: alex, type: type).where.not(rrule: nil).order(:starts_on, :id).each do |event|
        date = event.occurrence_dates_between(today + 1, today + 14).first or next
        record = event.occurrence_for(date)
        return record unless record.completed?
      end
      nil
    end

    # Alex's next visit to a doctor that's still to come.
    def upcoming_appointment
      Appointment.section_scope(:healthcare).where(profile: alex, rrule: nil, starts_on: (today + 1)..(today + 30))
        .order(:starts_on, :id).map(&:first_occurrence).find(&:pending?)
    end

    # Its notifications read a little later, like most are.
    def settle(subject, read: true)
      Notification.where(subject: subject).update_all(read_at: read ? Time.current + rng.rand(1..6).hours : nil)
      subject
    end
  end
end
