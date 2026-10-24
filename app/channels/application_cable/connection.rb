# frozen_string_literal: true

module ApplicationCable
  # Every cable connection belongs to a signed-in Profile, resolved from the
  # Devise/Warden session cookie. Anonymous connections are rejected, so
  # channels can trust `current_profile`.
  class Connection < ActionCable::Connection::Base
    identified_by :current_profile

    def connect
      self.current_profile = env["warden"]&.user(:profile) || reject_unauthorized_connection
    end
  end
end
