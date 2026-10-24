# frozen_string_literal: true

# Reverts an applied change set from its undo log, newest step first, in one
# transaction. Each kind of entry the operations logged is undone by its own
# step (Undoer::Step). Refuses when a record was changed after the set was
# applied, or when the set deleted something (deletions can't be undone).
module Assistant
  module ChangeSets
    class Undoer
      # key: assistant.change_sets.cannot_undo.<key> for the user; message for the model.
      class CannotUndo < StandardError
        attr_reader :key, :thing

        def initialize(message, key: :failed, thing: nil)
          super(message)
          @key = key
          @thing = thing
        end
      end

      # The step that undoes each kind of entry an operation writes
      # (Operations::UndoEntry). A kind with none (a deletion, a merge)
      # can't be undone.
      STEPS = {
        "created" => Created, "updated" => Updated, "status" => Status, "series" => Series, "uses" => Uses,
        "shared" => Shared, "unshared" => Unshared, "range" => SetRange,
        "item_checked" => ItemChecked, "item_unchecked" => ItemUnchecked, "requested" => Requested
      }.freeze

      def self.call(set) = new(set).call

      attr_reader :profile

      def initialize(set)
        @set = set
        @profile = set.profile
        @events = []
        @seen = Set.new
      end

      def call
        raise CannotUndo.new("only an applied change can be undone", key: :not_applied) unless @set.applied?
        raise CannotUndo.new("it deleted something, which can't be undone", key: :deleted) unless @set.undoable

        steps = @set.undo_log.reverse.map { |entry| step_for(entry) }
        ActiveRecord::Base.transaction do
          steps.each(&:undo!)
          @set.update!(status: :undone, undone_at: Time.current)
        end
        # The series the undo touched, as they are now: one it removed has
        # no day card left to refresh.
        Event.where(id: @events.map(&:id)).find_each { |event| Calendar::DayCardBroadcaster.call(event: event) }
        true
      end

      # The entry's record, nil when it is gone. Refuses when the record, or
      # a day's series, changed after the set was applied. This undo's own
      # writes don't count, because it may touch a record twice (a dose's
      # status, then its supplies).
      def record_for(entry)
        record = entry["model"].constantize.find_by(id: entry["id"])
        return unless record

        key = seen_key(record)
        unchanged_since!(record, record.updated_at, entry["updated_at"]) unless @seen.include?(key)
        if record.is_a?(Occurrence) && !@seen.include?("Event##{record.event_id}")
          unchanged_since!(record, record.event.updated_at, entry["event_updated_at"])
        end
        @seen << key
        @seen << "Event##{record.event_id}" if record.is_a?(Occurrence)
        record
      end

      def unchanged_since!(record, updated_at, stamp)
        return if stamp.blank? || updated_at.utc <= Time.iso8601(stamp) + 0.001

        thing = record.try(:event_label) || record.try(:name) || record.class.model_name.human
        raise CannotUndo.new("#{thing} was changed afterwards", key: :changed_since, thing: thing)
      end

      # A series whose day cards are pushed again once the undo commits.
      def refresh(event) = @events << event

      private

      def step_for(entry)
        step = STEPS.fetch(entry["kind"]) { raise CannotUndo.new("#{entry["kind"]} can't be undone", key: :deleted) }
        step.new(entry, self)
      end

      def seen_key(record) = "#{record.is_a?(Event) ? "Event" : record.class.name}##{record.id}"
    end
  end
end
