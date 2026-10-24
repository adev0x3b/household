# frozen_string_literal: true

module Lexicon
  class Import
    # An import's report as its record keeps it (LexiconImport#report): each
    # step marked as it runs, how far the streaming steps got, the counts so
    # far — saved on every change, so the admin page follows along, and told
    # to whoever asked (on_step). Marking a step running, or reporting its
    # progress, raises Cancelled when the record says someone asked the
    # import to stop.
    class Report
      # What a step's block answers when the step had nothing to do.
      Skip = Data.define(:detail)

      # The step running now, by name.
      attr_reader :current

      def initialize(import, counts:, on_step: nil)
        @import = import
        @counts = counts
        @on_step = on_step
      end

      # A step from start to end: the block answers its detail, or a Skip.
      def run(name)
        started = clock
        mark(name, "running")
        outcome = yield
        outcome.is_a?(Skip) ? mark(name, "skipped", outcome.detail) : mark(name, "ok", outcome, clock - started)
      end

      def mark(name, status, detail = nil, seconds = nil)
        if status == "running"
          raise Cancelled if @import.cancel_requested?

          @current = name
        end
        step = step_named(name)
        started = status == "running" ? Time.current.iso8601 : step["started_at"]
        step.merge!("status" => status, "detail" => detail, "seconds" => seconds&.round(1), "started_at" => started).compact!
        save
        @on_step&.call(step)
      end

      # How far the steps named are, while they run; and whether to stop.
      def progress(details)
        raise Cancelled if @import.cancel_requested?

        details.each { |name, text| step_named(name)["detail"] = text }
        save
      end

      # What a step found, under its own key (the checks, the dictionary's picks…).
      def keep(key, value)
        @import.report[key] = value
        save
      end

      def status_of(name) = step_named(name)["status"]

      private

      def step_named(name) = @import.report["steps"].find { _1["name"] == name }

      def save
        @import.report["counts"] = @counts.dup
        @import.report["updated_at"] = Time.current.iso8601
        @import.update_columns(report: @import.report, updated_at: Time.current)
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
