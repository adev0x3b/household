# frozen_string_literal: true

module Reports
  module Agenda
    # Things that need someone to act now, whatever period is selected:
    #
    #   :overdue_task          a task passed and still to do, however long
    #                          ago; urgent when it is high or urgent
    #   :appointment_outcome   an appointment that isn't medical, passed and
    #                          still pending, to record how it went
    #
    # Read from Reports::Unfinished, one item a series: its newest such day,
    # counting the others.
    class AttentionItems
      URGENT_PRIORITIES = %w[high urgent].freeze

      include Enumerable

      def initialize(today:, window:)
        @today = today
        @window = window
      end

      def each(&block) = items.each(&block)

      def items
        @items ||= AttentionItem.sorted(overdue_tasks + appointment_outcomes, today: @today)
      end

      private

      def overdue_tasks
        unfinished.latest(of: Task).map do |entry, count|
          severity = URGENT_PRIORITIES.include?(entry.details.priority) ? :critical : :warning
          AttentionItem.new(kind: :overdue_task, resolvable: true, severity: severity, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end

      def appointment_outcomes
        unfinished.latest(of: Appointment) { _1.section == :agenda }.map do |entry, count|
          AttentionItem.new(kind: :appointment_outcome, resolvable: true, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end

      def unfinished = @window.unfinished(today: @today)
    end
  end
end
