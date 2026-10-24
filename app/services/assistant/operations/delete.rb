# frozen_string_literal: true

module Assistant
  module Operations
    # Deletes one record (ref), several (fields ids), or everything of a type
    # (fields all: true, narrowed by query, date_from and date_to). Always
    # risky, because it can't be undone: it waits for the user's button.
    class Delete < Base
      MAX = 25
      UNSAVED = "that's an upcoming day of a repeating item with nothing saved: to stop the whole series use " \
                "whole_series; to skip just that day use mark_done with status skipped"

      def phase = :deleting
      def risky? = true
      def approval_kind = "destroy"

      def check
        @scope = resource.eventable? ? (fields["scope"].presence_in(Occurrences::Destroy::SCOPES) || "occurrence") : "occurrence"
        @records =
          if pinned?
            pinned_records
          elsif fields["all"].to_s == "true" || generic_ref?
            everything
          elsif fields["ids"].present?
            by_ids(Array(fields["ids"]))
          else
            [ resolve! ].compact
          end
        fail!("nothing matched, so nothing to delete") if @records.empty? && @candidates.empty?

        @records = @records.filter_map { |record| saved_for(record) }.uniq
        fail!(UNSAVED) if @records.empty? && @candidates.empty?

        allowed, refused = @records.partition { |record| Pundit.policy!(profile, record).destroy? }
        @notes << "not the user's to delete: #{refused.size}" if refused.any?
        fail!("the user isn't allowed to delete #{refused.size == 1 ? "it" : "those"}") if allowed.empty? && refused.any?
        @records = allowed
        ask_owner_for(@records, :destroy?)
        note_open_series
      end

      def checked_records = Array(@records)

      # The records as they are now, deleted together: the days through one
      # Occurrences::Destroy, the rest one by one.
      def apply!(applier)
        applier.not_undoable!
        fresh = current_records
        days, others = fresh.partition { |record| record.is_a?(Occurrence) }
        Occurrences::Destroy.call(days, by: profile, scope: @scope) if days.any?
        others.each do |record|
          Pundit.authorize(profile, record, :destroy?)
          record.destroy!
        end
        fresh.map { |record| entry("deleted", record) }
      end

      def label = @records.present? ? ProposalSummary.for_many(@records, scope: @scope) : super

      private

      # "delete all the cobalamin doses" without whole_series only removes
      # the ones already saved; the series still generates more. Said before
      # the button, not after: the confirm card's own summary already gives
      # a date away ("on September 3", not "every time it repeats"), but a
      # model doesn't reliably read that back.
      def note_open_series
        return unless @scope == "occurrence"

        ids = @records.filter_map { |record| record.event.id if record.respond_to?(:event) && record.event&.recurring? }.uniq
        return if ids.empty?

        @notes << "This only removes what's already saved; #{ids.one? ? "the series (event_id #{ids.first}) keeps" : "these series (event_id #{ids.join(", ")}) keep"} " \
                  "repeating. If the user means to stop it entirely, use whole_series: true instead."
      end

      # An upcoming day (a series id or day resolves to one, unsaved) stands
      # for its series when the whole series goes; alone there is nothing to
      # delete.
      def saved_for(record)
        return record if record.persisted?
        return unless @scope == "series" && record.is_a?(Occurrence)

        record.event.occurrences.in_order.first || record
      end

      # The records as they are now (one may have gone meanwhile): the saved
      # ones read again together, an upcoming day from its series.
      def current_records
        saved, upcoming = @records.partition(&:persisted?)
        saved = resource.where_accessible(profile, saved.map(&:id)).index_by(&:id)
        series = upcoming.any? ? Event.where(id: Event.accessible_by(profile).where(id: upcoming.map(&:event_id)).select(:id)).index_by(&:id) : {}
        @records.filter_map do |record|
          next saved[record.id] if record.persisted?

          series[record.event_id]&.occurrence_on(record.date, time: record.time_string)
        end
      end

      # "lab reports", "all my appointments": only type words, so everything
      # of that type (within a date the words name, if any).
      def generic_ref?
        return false if ref.blank? || ref.to_s.match?(/\A\$|\A\d+\z/)

        date, rest = ChangeSets::Resolver.split_date(ref.to_s)
        @ref_date = date
        (rest.downcase.scan(/[[:alnum:]]{2,}/) - ChangeSets::Resolver::STOPWORDS - %w[all every tutti tutte ogni]).empty?
      end

      def everything
        from = date(fields["date_from"]) || @ref_date
        to = date(fields["date_to"]) || @ref_date
        found = resource.search(profile, query: fields["query"], date_from: from, date_to: to, limit: MAX + 1).filter_map { |summary| summary[:id] }
        fail!("more than #{MAX} records match; narrow it down with query or dates") if found.size > MAX

        by_ids(found)
      end

      def by_ids(ids)
        ids = ids.map(&:to_i).uniq
        records = resource.where_accessible(profile, ids).to_a
        missing = ids - records.map(&:id)
        @notes << "not found: #{missing.join(", ")}" if missing.any?
        records.sort_by { |record| ids.index(record.id) }
      end

      def date(value) = value.present? ? DateWords.parse(value) : nil
    end
  end
end
