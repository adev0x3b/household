# frozen_string_literal: true

module Reports
  module Finance
    # Things that need someone to act now, whatever period is selected:
    #
    #   :overdue_transaction   a transaction (income or expense) whose day
    #                          has passed, however long ago, never logged —
    #                          a bill not yet paid, or income not yet
    #                          recorded. Both kinds lapse the same way, so
    #                          this doesn't split by kind.
    #
    # Read from Reports::Unfinished, as Healthcare's missed doses are: a
    # Transaction day is an Occurrence like any other. A payment a housemate
    # logged against the viewer is left out: it's theirs to log, the viewer
    # only reads it.
    class AttentionItems
      include Enumerable

      def initialize(audience:, today: Date.current, window: Window.new(audience))
        @audience = audience
        @today = today
        @window = window
      end

      def each(&block) = items.each(&block)

      def items
        @items ||= AttentionItem.sorted(overdue_transactions, today: @today)
      end

      private

      def overdue_transactions
        @window.unfinished(today: @today).latest(of: Transaction) { !_1.counterparty?(@audience.viewer) }.map do |entry, count|
          AttentionItem.new(kind: :overdue_transaction, resolvable: true, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end
    end
  end
end
