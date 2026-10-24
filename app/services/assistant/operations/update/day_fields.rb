# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # The fields of a day of a series, written where Occurrences::FormSave
      # puts them, so the assistant and the form agree: a one-off's on its
      # series, a repeating series' day's on the day alone, so the other
      # days keep the series' values.
      class DayFields < Fields
        def check
          normalize!
          normalize_times!
          validate
        end

        def preview_rows
          kind = record.event.class
          changes.map do |key, value|
            { "attribute" => key, "from" => LinkApproval.shown(kind, key, current_value(key)), "to" => LinkApproval.shown(kind, key, value) }
          end
        end

        def before
          event = record.event
          place = placements
          own = record.own_details
          { before: record.new_record? ? {} : snapshot(record, DAY_COLUMNS + SERIES_COLUMNS),
            series_before: (snapshot(event, SERIES_COLUMNS + [ "starts_on" ]) if place[:series].any?),
            series_details_before: (details_snapshot(event.details) if place[:series_details].any?),
            details_before: (details_snapshot(own) if own) }
        end

        def apply!(applier)
          Pundit.authorize(profile, record, record.persisted? ? :update? : :edit?)
          event = record.event
          place = placements
          @materialized = record.new_record?
          @had_own_details = record.own_details.present?
          old_date = record.date
          old_time = record.time_string

          record.assign_own(place[:day])
          record.save!
          event.update!(place[:series]) if place[:series].any?
          event.details.update!(place[:series_details]) if place[:series_details].any?
          record.write_details!(place[:day_details]) if place[:day_details].any?
          @moved_from = skip_old_slot!(old_date, old_time)
          @completed = complete_if_past!(old_date)
          dates = old_date == record.date ? [] : [ old_date ]
          applier.defer([ -> { Calendar::DayCardBroadcaster.call(event: event, dates: dates) } ])
          []
        end

        # Asked once every part has written, since another part (a meal's
        # recipes) may have given the day its own details row.
        def outcome
          { materialized: @materialized, completed: @completed, moved_from: @moved_from,
            details_created: !@had_own_details && record.own_details.present? }
        end

        private

        # Where each change goes: the day's columns, the series' columns and
        # details row, or the day's details override row.
        def placements
          @placements ||= begin
            day = changes.slice(*DAY_COLUMNS)
            universal = changes.slice(*SERIES_COLUMNS)
            details = changes.except(*DAY_COLUMNS, *SERIES_COLUMNS)
            if series_scope?
              series = universal.dup
              series["starts_on"] = day["date"] if day.key?("date")
              { day: day, series: series, series_details: details, day_details: {} }
            else
              whole = details.slice(*SERIES_ONLY.fetch(record.event.type.underscore, []))
              { day: day.merge(universal), series: {}, series_details: whole, day_details: details.except(*whole.keys) }
            end
          end
        end

        # A dose's time or anchor said in words ("dinner", "8pm").
        def normalize_times!
          if changes.key?("anchor")
            code = Events::TimesOfDay.code_for(changes["anchor"])
            fail!("can't read the time #{changes["anchor"].inspect} — give breakfast / lunch / dinner / bedtime") unless code && Events::TimesOfDay.anchor?(code)
            changes["anchor"] = code
            changes["time"] ||= Events::TimesOfDay.hhmm(code)
          end
          return unless changes.key?("time")

          code = Events::TimesOfDay.code_for(changes["time"])
          fail!("can't read the time #{changes["time"].inspect} — give HH:MM") unless code
          changes["time"] = Events::TimesOfDay.hhmm(code)
          changes["anchor"] ||= (code if Events::TimesOfDay.anchor?(code))
        end

        # The changes checked as they would be saved, then put back.
        def validate
          place = placements
          event = record.event
          day_before = record.attributes.slice(*place[:day].keys)
          begin
            record.assign_own(place[:day])
            event.assign_attributes(place[:series])
            event.details.assign_attributes(place[:series_details])
            override = record.override_details.tap { |row| row.assign_own(place[:day_details]) } if place[:day_details].any?
            [ record, event, override ].compact.each do |object|
              object.validate
              object.errors.each { |error| problems << "#{field_name(error.attribute)} #{error.message}" }
            end
          ensure
            record.persisted? ? record.restore_attributes : record.assign_attributes(day_before)
            event.restore_attributes
            event.details.restore_attributes
            override.restore_attributes if override&.persisted?
          end
        end

        # A field by the name the model knows it under.
        def field_name(attribute)
          name = attribute.to_s.delete_prefix("details.")
          Draft::FIELD_NAMES.fetch(name, name)
        end

        # A field as the day reads it now.
        def current_value(key)
          return record[key] if DAY_COLUMNS.include?(key) || (!record.respond_to?(key) && record.has_attribute?(key))
          return record.public_send(key) if SERIES_COLUMNS.include?(key)

          record.details.public_send(key)
        end

        # A day of a repeating series moved to another date: its slot on the
        # old date is removed from the series, so it isn't projected again.
        def skip_old_slot!(old_date, old_time)
          event = record.event
          return unless event.recurring? && (record.date != old_date || record.time_string != old_time)
          return unless event.occurrence_dates_between(old_date, old_date).include?(old_date)
          return if event.event_exclusions.any? { |exclusion| exclusion.date == old_date && exclusion.time_string == old_time }

          event.skip!(old_date, time: old_time)
          [ old_date.iso8601, old_time ]
        end

        # A pending day moved into the past was done then.
        def complete_if_past!(old_date)
          return false unless record.date < old_date && record.date < Date.current && record.pending?

          record.complete!
          true
        end
      end
    end
  end
end
