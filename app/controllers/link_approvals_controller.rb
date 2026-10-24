# frozen_string_literal: true

# A linked housemate's request about one's item, dropped: declined by its
# owner (Links::Approvals::Decide, who tells the asker), or taken back by
# its asker. Giving it is LinkApprovalConsentsController.
class LinkApprovalsController < ApplicationController
  include LinksPageAnswers

  def destroy
    approval = LinkApproval.involving(current_profile).find(params[:id])
    authorize approval

    if approval.owner_id == current_profile.id
      Links::Approvals::Decide.call(approval, approve: false)
      answer_link_change(:success, t("links.notices.approval_declined"))
    else
      withdraw(approval)
    end
  rescue Links::Approvals::Decide::Decided
    refuse(t("links.notices.decided"))
  end

  private

  def withdraw(approval)
    return refuse(t("links.notices.decided")) unless approval.live?

    approval.update!(status: :withdrawn, decided_at: Time.current)
    Links::Approvals::Decide.settled(approval)
    answer_link_change(:success, t("links.notices.withdrawn"))
  end
end
