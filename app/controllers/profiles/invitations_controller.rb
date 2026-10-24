# frozen_string_literal: true

# Accepting an invitation: the link handed over (or in the email) opens a
# form to choose a username and a password, and the person is in. Inviting
# is HouseholdInvitationsController; this app has no sign-up.
class Profiles::InvitationsController < Devise::InvitationsController
  # An invitation's token can't be guessed; trying anyway is slowed like signing in.
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { rate_limited }

  # GET /profiles/invitation/accept?invitation_token=...
  def edit
    resource.invitation_token = params[:invitation_token]
    render form
  end

  # PUT /profiles/invitation
  def update
    super do |profile|
      next if profile.errors.empty?
      # A token that opens no invitation (used, cancelled, guessed): the same
      # answer as opening a dead link, not a form for nobody.
      return dead_link if profile.new_record?

      profile.invitation_token = params.dig(resource_name, :invitation_token)
      return render form, status: :unprocessable_content
    end
  end

  private

  # Whoever accepts is in the household in the same transaction, with what
  # a member has from the start.
  def accept_resource
    Profile.transaction do
      super.tap { |profile| Profiles::Join.call(profile) if profile.errors.empty? }
    end
  end

  def dead_link
    toast_flash(:alert, t("devise.invitations.invitation_token_invalid"))
    redirect_to new_profile_session_path, status: :see_other
  end

  def form = Views::Devise::Invitations::Edit.new(resource: resource, resource_name: resource_name)
end
