# frozen_string_literal: true

# Runs an assistant's held operation (LinkApproval from the assistant, its
# op pinned to one record) as the item's owner, once they approve: checked
# again against today's data, then applied as the assistant would have —
# without a chat or a change set, its broadcasts held until the decision
# commits. Raises Apply::Failed when it no longer checks out.
module Links
  module Approvals
    class OperationRunner
      # What operations call on their applier while writing.
      class Applier
        def initialize = @broadcasts = []
        def defer(broadcasts) = @broadcasts.concat(broadcasts)
        def saved(_summaries) = nil
        def remember(_handle, _record) = nil
        def not_undoable! = nil
        def finish = ActiveRecord.after_all_transactions_commit { @broadcasts.each(&:call) }
      end

      Set = Struct.new(:profile, :chat, :acknowledged_warnings)

      def self.call(approval)
        context = Assistant::ChangeSets::Context.for(Set.new(approval.owner, nil, []))
        op = Assistant::Operations.build(approval.payload.fetch("spec"), index: 0, context: context).compile
        unless op.ready? && !op.held?
          raise Apply::Failed.new(:changed, (op.problems + op.missing.map(&:to_s)).to_sentence.presence || "it no longer checks out")
        end

        applier = Applier.new
        op.apply!(applier)
        applier.finish
      end
    end
  end
end
