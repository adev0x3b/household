# frozen_string_literal: true

module Setup
  # The first setup's first step: the person setting the copy up, who
  # becomes its admin and the household's owner. Checked as the profile it
  # will be, so the rules are Profile's own.
  class Account
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :first_name, :string
    attribute :last_name, :string
    attribute :username, :string
    attribute :email, :string
    attribute :password, :string
    attribute :password_confirmation, :string
    attribute :locale, :string

    validate :as_a_profile

    def self.param_key = :account

    def self.fields = attribute_names.map(&:to_sym)

    # In the language the page is shown in, which is the browser's.
    def self.for_setup = new(locale: I18n.locale.to_s)

    def assign(values)
      given = values.to_h.symbolize_keys
      self.first_name = given[:first_name].to_s.squish.presence
      self.last_name = given[:last_name].to_s.squish.presence
      self.username = given[:username].to_s.strip.presence
      self.email = given[:email].to_s.strip.presence
      self.password = given[:password]
      self.password_confirmation = given[:password_confirmation]
      self.locale = given[:locale].presence || locale
      self
    end

    def asked?(_form) = true

    # What Admins::Create takes from this step.
    def to_admin
      { first_name:, last_name:, username:, email:, password:, password_confirmation:, locale: }
    end

    private

    # The household is the next step's, so its errors are left to it.
    def as_a_profile
      profile = Profile.new(household: ::Household.new, role: :admin, **to_admin)
      return if profile.valid?

      profile.errors.each { |error| errors.import(error) unless error.attribute == :household }
    end
  end
end
