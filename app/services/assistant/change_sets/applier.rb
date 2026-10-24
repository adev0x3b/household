# frozen_string_literal: true

# Applies a compiled change set through its operations in one transaction,
# all or nothing, and records how to undo it. The calendar is refreshed once
# the outermost transaction commits, since a caller such as Submit may hold
# one open around this one.
module Assistant
  module ChangeSets
    class Applier
      class NotReady < StandardError; end

      def self.call(set, confirmed: false) = new(set).call(confirmed:)

      attr_reader :summaries

      def initialize(set)
        @set = set
        @broadcasts = []
        @handles = {}
        @summaries = []
        @undoable = true
      end

      # confirmed: the user pressed Apply (needed for risky sets).
      #
      # The set's row is locked first and its status read again, so a second
      # press (another tab, a double tap) waits for the first and then finds
      # it applied, instead of applying it twice. A set waiting for the
      # button was pinned to the records its card listed (Submit), so it is
      # compiled against exactly those.
      def call(confirmed: false)
        result = nil
        log = []
        reviews = {}
        ActiveRecord::Base.transaction do
          @set.lock!
          raise NotReady, "change set #{@set.id} is #{@set.status}" unless @set.in_progress?

          result = Compiler.call(@set)
          allowed = result.ready? || (confirmed && result.status == :confirm)
          raise NotReady, "change set #{@set.id} is #{result.status}" unless allowed

          result.operations.sort_by { |op| [ op.apply_order, op.index ] }.each do |op|
            # A linked housemate's item they must OK first: asked, not written.
            entries = op.held? ? Links::Approvals::Hold.from_operation(op) : op.apply!(self)
            reviews[op.index] = Review.row_record(entries)
            log.concat(entries)
          end
          applied_at = Time.current
          stamp(log, applied_at)
          @set.update!(status: :applied, undo_log: log, undoable: @undoable, applied_at: applied_at,
                       acknowledged_warnings: @set.acknowledged_warnings | result.operations.flat_map(&:warning_keys),
                       display: result.operations.map { |op|
                         { "intent" => op.intent, "summary" => op.summary, "status" => op.held? ? "asked" : "applied",
                           "review" => reviews[op.index] }.compact
                       })
        end
        broadcasts = @broadcasts
        ActiveRecord.after_all_transactions_commit { broadcasts.each(&:call) }
        result
      end

      # Called by operations while applying.
      def defer(broadcasts) = @broadcasts.concat(broadcasts)
      def saved(summaries) = @summaries.concat(summaries)
      def remember(handle, record) = handle && (@handles[handle] = record)
      def not_undoable! = @undoable = false

      private

      # Each record the set left, and a day's series too (a one-off's fields
      # live there), is stamped with the moment the set finished, so undo
      # can refuse a record changed after it. The moment rather than the
      # rows' updated_at, because a series or day its details touched is
      # written at commit (touch_later), after this reads, with an earlier
      # time.
      def stamp(log, at)
        at = at.utc.iso8601(6)
        named = log.select { |entry| entry["model"] && entry["id"] }
        left = named.group_by { |entry| entry["model"] }.to_h do |model, entries|
          [ model, model.constantize.where(id: entries.map { |entry| entry["id"] }).pluck(:id).to_set(&:to_s) ]
        end
        named.each do |entry|
          next unless left[entry["model"]].include?(entry["id"].to_s)

          entry["updated_at"] = at
          entry["event_updated_at"] = at if entry["model"] == "Occurrence"
        end
      end
    end
  end
end
