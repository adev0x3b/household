# frozen_string_literal: true

module Profiles
  # A person's live connections, closed once their password changes
  # (Profiles::AfterPasswordChange): a browser that change signed out stops
  # hearing about the household now rather than at its next page. Every
  # browser connects again, and only one still signed in is let back in
  # (ApplicationCable::Connection).
  class Broadcaster < ApplicationBroadcaster
    def self.disconnect(profile)
      quietly { ActionCable.server.remote_connections.where(current_profile: profile).disconnect }
    end
  end
end
