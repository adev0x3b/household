# frozen_string_literal: true

module Delivery
  # When the deploy token expires, as GitHub last said in an answer's
  # headers, and how soon that is. Nothing is known until the token has
  # been used once.
  class TokenExpiry
    # How close the end must be before the console and the settings page warn.
    WARNING_DAYS = 14

    def self.current = new(Github.token_expires_at)

    attr_reader :expires_at

    def initialize(expires_at)
      @expires_at = expires_at
    end

    def known? = expires_at.present?

    # Whole days left, rounded up: 0 or less once it has expired.
    def days_left = ((expires_at - Time.current) / 1.day).ceil

    def expired? = known? && days_left <= 0
    def soon? = known? && days_left <= WARNING_DAYS
  end
end
