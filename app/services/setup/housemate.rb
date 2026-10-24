# frozen_string_literal: true

module Setup
  # One person the first setup invites (Setup::Housemates): an email, and a
  # first name to greet them by.
  class Housemate
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :first_name, :string
    attribute :email, :string

    validates :email, format: { with: Devise.email_regexp }

    def self.from(values)
      given = values.to_h.symbolize_keys
      new(first_name: given[:first_name].to_s.squish.presence, email: given[:email].to_s.strip.downcase.presence)
    end

    # A row left empty is no one.
    def blank? = first_name.nil? && email.nil?
  end
end
