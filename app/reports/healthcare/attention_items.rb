# frozen_string_literal: true

module Reports
  module Healthcare
    # Things that need someone to act now, whatever period is selected:
    #
    #   :missed_dose           a dose passed and not taken, however long ago
    #   :overdue_dose          a dose due today at a set time, past it (and
    #                          the grace for its kind of schedule) and still
    #                          not taken
    #   :skipped_dose          a dose skipped in the last 7 days for a reason
    #                          someone can do something about (it wasn't
    #                          there, it was forgotten)
    #   :appointment_outcome   a past visit still pending, however long ago
    #   :pending_lab_result    a past lab result still pending, however long ago
    #   :supply_running_out    14 days of stock or fewer
    #   :supply_low_stock      under its low-stock threshold, at a pace that
    #                          can't be told
    #   :batch_expiring        a batch with stock left that expires within
    #                          30 days
    #   :batch_expired         a batch with stock left that has expired
    #   :critical_lab_value    a value past a critical bound (last 90 days:
    #                          Labs::CRITICAL_DAYS)
    #
    # The days passed and still to do come from Unfinished, every one
    # whatever its date, one item a series: its newest such day, counting
    # the others.
    class AttentionItems
      SKIPPED_DOSE_WINDOW = 7
      # How long after its time a dose may still be taken before it's
      # overdue (ISMP's windows): an hour when there are several a day,
      # two when there is one.
      OVERDUE_GRACE = { several: 1.hour, single: 2.hours }.freeze
      ACTIONABLE_REASONS = %w[not_available forgot].freeze

      include Enumerable

      # `now` is read on the viewer's clock (Profile#zone) for what is
      # overdue today.
      def initialize(audience:, supplies:, labs:, today: Date.current, now: Time.current, window: Window.new(audience))
        @audience = audience
        @supplies = supplies
        @labs = labs
        @today = today
        @now = now
        @window = window
      end

      def each(&block) = items.each(&block)

      def items
        @items ||= AttentionItem.sorted([
                                          *missed_doses, *overdue_doses, *skipped_doses, *appointment_outcomes, *pending_lab_results,
                                          *supplies_running_out, *expiring_batches, *critical_lab_values
                                        ], today: @today)
      end

      private

      def missed_doses
        unfinished.latest(of: Medication).map do |entry, count|
          AttentionItem.new(kind: :missed_dose, resolvable: true, severity: :critical, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end

      def overdue_doses
        zone = @audience.viewer.zone
        doses.filter_map do |entry|
          next unless entry.due_today? && entry.time

          hour, minute = Events::TimesOfDay.clock(entry.time)
          due = zone.local(@today.year, @today.month, @today.day, hour, minute)
          grace = OVERDUE_GRACE.fetch(entry.event.slots.size > 1 ? :several : :single)
          next unless due + grace <= @now

          AttentionItem.new(
            kind: :overdue_dose, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence,
            words: { time: entry.occurrence.time_label },
          )
        end
      end

      def skipped_doses
        doses.filter_map do |entry|
          reason = entry.occurrence.skipped_reason
          next unless entry.skipped? && ACTIONABLE_REASONS.include?(reason)

          AttentionItem.new(
            kind: :skipped_dose, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence,
            words: { reason: I18n.t("medications.skipped_reason.#{reason}") },
          )
        end
      end

      def appointment_outcomes
        unfinished.latest(of: Appointment) { _1.section == :healthcare }.map do |entry, count|
          AttentionItem.new(kind: :appointment_outcome, resolvable: true, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end

      def pending_lab_results
        unfinished.latest(of: LabTestResult).map do |entry, count|
          AttentionItem.new(kind: :pending_lab_result, resolvable: true, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end

      def supplies_running_out
        @supplies.attention_rows.map do |row|
          if row.days_left
            AttentionItem.new(
              kind: :supply_running_out, severity: :critical, subject: row.supply, date: row.depletion_date(@today), opens: row.supply,
              words: { count: row.days_left },
            )
          else
            AttentionItem.new(kind: :supply_low_stock, severity: :critical, subject: row.supply, date: nil, opens: row.supply)
          end
        end
      end

      def expiring_batches
        @supplies.expiring_rows.map do |row|
          if row.expired?(@today)
            AttentionItem.new(kind: :batch_expired, severity: :critical, subject: row.supply, date: row.expires_on, opens: row.purchase)
          else
            AttentionItem.new(kind: :batch_expiring, severity: :warning, subject: row.supply, date: row.expires_on, opens: row.purchase)
          end
        end
      end

      # A critical value opens the lab result's day it was measured on.
      def critical_lab_values
        @labs.critical_readings.map do |entry, reading|
          AttentionItem.new(
            kind: :critical_lab_value, severity: :critical, subject: entry.analyte.name, date: reading.date, occurrence: entry.occurrence,
            words: { value: [ reading.value, entry.unit&.name ].compact.join(" ") },
          )
        end
      end

      def unfinished = @window.unfinished(today: @today)

      # Every dose of the last week, today's included, for what is late
      # today and what was skipped for a reason someone can act on.
      def doses
        @doses ||= begin
          days = Period.new(start_date: @today - SKIPPED_DOSE_WINDOW, end_date: @today)
          @window.ledger(days, today: @today, of: Medication).entries
        end
      end
    end
  end
end
