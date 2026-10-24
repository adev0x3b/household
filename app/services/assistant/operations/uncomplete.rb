# frozen_string_literal: true

module Assistant
  module Operations
    # Marks a done item as not done again. A cost that was paid with it
    # goes back to pending. Never guesses the one due today: what is to be
    # undone was named.
    class Uncomplete < StatusChange
      def approval_kind = "uncomplete"

      private

      def target_status = "pending"

      def following_costs(record) = record.costs.select(&:completed?)

      def picks_the_one_due_today? = false
    end
  end
end
