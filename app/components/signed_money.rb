# frozen_string_literal: true

# An amount with the way it went: "-€42.00" spent, "+€1,200.00" received.
# Reports::Money is always a magnitude, so the sign is drawn here.
class Components::SignedMoney < Components::Base
  def initialize(cents:, currency:)
    @cents = cents
    @currency = currency
  end

  def view_template
    plain "#{@cents.negative? ? "-" : "+"}#{Reports::Money.new(cents: @cents.abs, currency: @currency)}"
  end
end
