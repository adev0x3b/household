# frozen_string_literal: true

module Assistant
  module Operations
    # Marks an item done: a visit, a dose, a task, a payment. Its pending
    # costs follow, and a dose may say which supplies it used (fields.uses),
    # drawn from stock as it completes.
    class Complete < StatusChange
      def approval_kind = "complete"

      private

      def target_status = "completed"

      def following_costs(record) = record.costs.select(&:pending?)

      # "I took it, I used a needle": the supplies this dose used, instead
      # of the ones copied from its series.
      def check_uses
        return if fields["uses"].blank?

        fail!("uses is only for a medication dose") unless resource.doses?
        @uses = SupplyUses.new(profile, fields["uses"], bought: context.supplies_bought)
        fail!(@uses.problem) if @uses.unknown.any?
      end
    end
  end
end
