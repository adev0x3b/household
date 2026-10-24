# frozen_string_literal: true

# The owner's consent to a linked housemate's held request: the change is
# made as the owner (Links::Approvals::Decide), or the request records why
# it couldn't be.
class LinkApprovalConsentsController < ApplicationController
  include LinksPageAnswers

  def create
    approval = LinkApproval.involving(current_profile).find(params[:link_approval_id])
    authorize approval, :approve?
    Links::Approvals::Decide.call(approval, approve: true)

    if approval.failed?
      answer_link_change(:alert, t("links.notices.approval_failed", reason: t("links.approvals.failures.#{approval.failure}")))
    else
      answer_link_change(:success, t("links.notices.approved"))
    end
  rescue Links::Approvals::Decide::Decided
    refuse(t("links.notices.decided"))
  end
end
