# frozen_string_literal: true

module Profiles
  # "Forgot your password?" asked (Profiles::PasswordsController#create),
  # with the id the typed login found, or nil: decided here, away from the
  # request, so neither its answer nor its time says whether the account
  # exists. The typed login itself never reaches the queue.
  class PasswordLinkRequestJob < ApplicationJob
    def perform(profile_id)
      profile = Profile.find_by(id: profile_id) or return

      RequestPasswordLink.call(profile)
    end
  end
end
