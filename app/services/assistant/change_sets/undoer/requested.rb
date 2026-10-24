# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A linked housemate asked to OK a change: the request is taken back
      # while it waits.
      class Requested < Step
        private

        def record = LinkApproval.find_by(id: entry["id"])

        def revert(approval)
          raise CannotUndo.new("#{approval.owner.display_name} already answered", key: :decided, thing: approval.owner.display_name) unless approval.live?

          approval.update!(status: :withdrawn, decided_at: Time.current)
          Links::Approvals::Decide.settled(approval)
        end
      end
    end
  end
end
