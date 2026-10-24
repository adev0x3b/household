# frozen_string_literal: true

module Households
  # Takes back an invitation nobody answered. It owns nothing yet, so the
  # profile goes as it is (Profile declares no `dependent:`, and a joined
  # member is removed by Profiles::Destroy instead). Returns the invitation.
  #
  #   Households::CancelInvitation.call(invitation)
  class CancelInvitation
    def self.call(invitation)
      raise ArgumentError, "#{invitation.email} has already joined" unless invitation.invitation_pending?

      invitation.destroy!
    end
  end
end
