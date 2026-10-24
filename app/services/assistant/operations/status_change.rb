# frozen_string_literal: true

module Assistant
  module Operations
    # What marking an item done, not done or skipped have in common: finding
    # the items, checking the user may, and the write. A subclass says the
    # status it sets and what follows it.
    class StatusChange < Base
      MAX = 25

      def phase = :finishing

      def check
        fail!("#{type} can't be marked done") unless resource.completable?
        @status = target_status
        @records =
          if pinned? then pinned_records
          elsif fields["all"].to_s == "true" then everything
          else [ resolve! || due_today ].compact
          end
        fail!("nothing still pending matched") if @records.empty? && fields["all"].to_s == "true"

        @records.each do |record|
          Pundit.authorize(profile, record, :change_status?)
          @notes << "#{record.event_label} is already #{@status.humanize(capitalize: false)}" if record.persisted? && record.status == @status
        end
        ask_owner_for(@records, :change_status?)
        check_uses
        check_reason
      end

      def checked_records = Array(@records)

      def apply!(applier)
        @records.flat_map do |record|
          next [] if record.persisted? && record.status == @status

          targets = [ [ record, @status ] ]
          targets += following_costs(record).map { |cost| [ cost, @status ] } if record.persisted? && record.event.costable?

          targets.flat_map do |target, status|
            Pundit.authorize(profile, target, :change_status?)
            materialized = target.new_record?
            previous = target.status.to_s
            uses = (@uses && target.event.is_a?(Medication)) ? use_supplies(target) : []
            target.edited_by(profile).change_status!(status, reason: (fields["skipped_reason"].presence if status == "skipped"))
            event = target.event
            applier.defer([ -> { Calendar::DayCardBroadcaster.call(event: event) } ])
            applier.saved([ summarize(target.reload) ])
            [ *uses, entry("status", target, from: previous, to: status, materialized: materialized) ]
          end
        end
      end

      def label
        return super if @records.blank?

        @records.map { |r| Resources.on_date(r.event_label, r) }.to_sentence
      end

      def waits_for_purchase? = @uses.present? && @uses.pending?

      private

      def target_status = raise(NotImplementedError, "#{self.class} must say the status it sets")

      # The costs of a record that change status with it: a visit's unpaid
      # fee is paid when the visit is done. None unless a subclass says so.
      def following_costs(_record) = []

      # Whether "Appointment done!" on the day may pick, among several
      # matches, the only one still pending today.
      def picks_the_one_due_today? = true

      # The supplies a dose used ("I took it, I used a needle") are only for
      # a dose being marked done.
      def check_uses
        fail!("uses is for a dose being marked done") if fields["uses"].present?
      end

      # Why a dose wasn't taken (Medication.skip_reasons), with "skipped".
      def check_reason
        reason = fields["skipped_reason"].presence
        return if reason.nil?

        fail!("skipped_reason goes with status skipped") unless @status == "skipped"
        reasons = resource.type.skip_reasons
        fail!("skipped_reason must be one of: #{reasons.join(", ")}") unless reasons.include?(reason.to_s)
      end

      # This dose's own list (Medication#replace_uses_for!, saving the day),
      # drawn from stock as it completes. Undone back to what it had.
      def use_supplies(dose)
        own = dose.persisted? ? dose.own_details : nil
        before = own&.supply_uses&.any? ? own.uses_list : nil
        materialized = dose.new_record?
        dose.event.replace_uses_for!(dose, @uses.list!)
        materialized ? [] : [ entry("uses", dose, before: before) ]
      end

      # Everything still pending in the range (and matching the words), the
      # upcoming occurrences of series included, saved as they're changed.
      def everything
        from = date_field("date_from")
        to = date_field("date_to") || from
        from ||= to
        found = resource.search(profile, query: fields["query"].presence, date_from: from, date_to: to, status: "pending", limit: MAX + 1)
        fail!("more than #{MAX} items match; narrow it down with query or dates") if found.size > MAX
        found.filter_map do |item|
          next resource.find_accessible(profile, item[:id]) if item[:id]

          event = Event.accessible_by(profile).of_type(resource.type).find(item[:event_id])
          event.occurrence_for(Date.iso8601(item[:date]), time: item[:time])
        end
      end

      def date_field(key)
        return if fields[key].blank?

        date = DateWords.parse(fields[key].to_s)
        fail!("can't read the date #{fields[key].inspect}") unless date

        date
      end

      # Of several matches, the only one still pending today is the one the
      # user means.
      def due_today
        return unless picks_the_one_due_today? && @candidates.present?

        due = @candidates.map(&:with_indifferent_access).select { |c| c[:date] == Date.current.iso8601 && c[:status] == "pending" }
        return unless due.one?

        @candidates = []
        @notes << "picked the one due today"
        pick = due.sole
        return resource.find_accessible(profile, pick[:id]) if pick[:id]

        event = Event.accessible_by(profile).of_type(resource.type).find(pick[:event_id])
        event.occurrence_for(Date.current, time: pick[:time])
      end
    end
  end
end
