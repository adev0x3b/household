# frozen_string_literal: true

module Accounts
  # Changing one's password on the Account page: the one in use, then the
  # new one twice, held to Profile's own rules. What follows any change of
  # password (Profiles::AfterPasswordChange) is the caller's, which knows
  # the browser it was made from.
  #
  #   change = Accounts::PasswordChange.new(current_profile, params.expect(password_change: [ … ]))
  #   change.save   # false: change.errors says why
  class PasswordChange
    include ActiveModel::Model
    include ActiveModel::Attributes

    FIELDS = %i[password password_confirmation].freeze

    attribute :current_password, :string
    attribute :password, :string
    attribute :password_confirmation, :string

    validates :current_password, presence: true
    validate :as_a_password

    def initialize(profile, values = {})
      @profile = profile
      super(values)
    end

    def save
      return false if invalid?
      return refused(:current_password, :invalid) unless @profile.try_password(current_password)

      @profile.update!(password:, password_confirmation:)
      true
    end

    private

    # Devise's rules (its length, the two alike, not blank), checked on a
    # profile that is nothing but the password, so the person's own record
    # never holds a password it refused.
    def as_a_password
      candidate = Profile.new(password:, password_confirmation:)
      candidate.valid?
      candidate.errors.each { |error| errors.import(error) if FIELDS.include?(error.attribute) }
    end

    def refused(attribute, error)
      errors.add(attribute, error)
      false
    end
  end
end
