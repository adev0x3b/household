# frozen_string_literal: true

module Occurrences
  class FormSave
    # The series' side of a form, under `event`: its rule, its collection,
    # its times of the day and the submitter's "Remind me" rows.
    class SeriesShape
      PARAMS = [ :frequency, :interval, :ends, :collection_id, :reminders_submitted, :slots_submitted,
                 { week_days: [], reminders: %i[amount unit], slots: [] } ].freeze

      def initialize(params, actor:)
        @params = params.to_h.with_indifferent_access
        @actor = actor
      end

      # Whether the form carried the rule at all: a day's quick form doesn't.
      def submitted? = @params.key?(:frequency)
      def frequency = @params[:frequency]
      # Whether it carried the times of the day: a medication's form does.
      def slots_submitted? = @params[:slots_submitted].present?
      # The times of the day sent, nil when the form has none.
      def slots = (Array(@params[:slots]).compact_blank if slots_submitted?)

      # The rule the fields make, nil for a one-off. Fields that can't make
      # one leave the shape invalid, which fails the save as the form's
      # error rather than the series'.
      def rule
        return @rule if defined?(@rule)

        @rule = Events::RecurrenceRule.build(frequency: frequency, interval: @params[:interval],
                                             week_days: @params[:week_days], ends: @params[:ends])
      rescue Events::RecurrenceRule::Invalid
        @invalid = true
        @rule = nil
      end

      def valid?
        rule
        !@invalid
      end

      # Gives the series its collection when the form carried it or the
      # series is new, and a new series its rule and times of the day. A
      # series that exists takes those through Events::Reschedule, once its
      # day is saved (FormSave#reschedule_series!).
      def apply_to(event)
        return unless submitted? || event.new_record?

        if event.new_record?
          event.rrule = rule
          event.assign_slots(slots) if slots
        end
        event.collection_id = collection_id_for(event) if @params.key?(:collection_id) || event.new_record?
      end

      # Whether the form carried a rule or times for a series that exists.
      def reschedules?(event) = event.persisted? && (submitted? || slots_submitted?)

      # The rule the series goes on with: the one sent, else its own.
      def rule_for(event) = submitted? ? rule : event.rrule

      # Whether the rule, the times or the collection sent differ from the series'.
      def changed_for?(event)
        (submitted? && Events::RecurrenceRule.describe(rule) != Events::RecurrenceRule.describe(event.rrule)) ||
          (slots_submitted? && event.slots_differ_from?(slots)) ||
          (@params.key?(:collection_id) && collection_id_for(event) != event.collection_id)
      end

      # The submitter's own reminders, replaced as a set when the form
      # carried them.
      def save_reminders_for(event)
        return if @params[:reminders_submitted].blank?

        rows = @params[:reminders] || {}
        rows = rows.to_h.values if rows.respond_to?(:keys)
        Events::SetReminders.call(event, profile: @actor, entries: rows)
      end

      # What a held request keeps of the shape: the reminders are the
      # asker's own and are saved at once.
      def payload = @params.to_h.except("reminders_submitted", "reminders")

      private

      # The collection is checked against what the actor can reach, and
      # what the owner can, since the series becomes theirs.
      def collection_id_for(event)
        id = @params[:collection_id]
        return nil if id.blank?

        scope = Collection.accessible_by(@actor).where(id: id)
        scope = scope.merge(Collection.accessible_by(event.profile)) if event.profile && event.profile != @actor
        scope.pick(:id)
      end
    end
  end
end
