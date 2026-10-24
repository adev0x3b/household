# frozen_string_literal: true

module Households
  # A new link for an invitation still waiting, from the household's list:
  # the old link stops working, and the new one is shown once to copy, like
  # the first (Households::Invite::Result).
  #
  #   result = Households::RenewInvitation.call(invitation, by: current_profile)
  #   result.token   # the new link's
  class RenewInvitation
    def self.call(invitation, by:)
      raise ArgumentError, "#{invitation.email} has already joined" unless invitation.invitation_pending?

      Invite::Result.new(profile: invitation, token: invitation.issue_invitation!(by), error: nil)
    end
  end
end
