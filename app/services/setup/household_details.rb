# frozen_string_literal: true

module Setup
  # The first setup's household: its name and the currency it counts in.
  class HouseholdDetails
    include ActiveModel::Model
    include ActiveModel::Attributes

    # Offered as suggestions; any ISO 4217 code is taken.
    CURRENCIES = %w[EUR USD GBP CHF CAD AUD JPY SEK NOK DKK PLN CZK].freeze

    attribute :name, :string
    attribute :currency, :string

    validate :as_a_household

    def self.param_key = :household

    def self.fields = attribute_names.map(&:to_sym)

    def self.for_setup = new(currency: ::Household.new.currency)

    def assign(values)
      given = values.to_h.symbolize_keys
      self.name = given[:name].to_s.squish.presence
      self.currency = given[:currency].to_s.strip.upcase.presence || currency
      self
    end

    def asked?(_form) = true

    private

    # The slug is made from the name, so a name it can't be made from is the
    # name's error, said only when the name has none of its own.
    def as_a_household
      household = ::Household.new(name:, currency:)
      return if household.valid?

      household.errors.each { |error| errors.import(error) unless error.attribute == :slug }
      household.errors.where(:slug).each { |error| errors.import(error, attribute: :name) } if errors[:name].none?
    end
  end
end
