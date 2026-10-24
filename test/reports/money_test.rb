# frozen_string_literal: true

require "test_helper"

class Reports::MoneyTest < ActiveSupport::TestCase
  test "arithmetic across currencies raises" do
    assert_raises(ArgumentError) do
      Reports::Money.new(cents: 1, currency: "EUR") + Reports::Money.new(cents: 1, currency: "USD")
    end
  end

  test "formats with the currency symbol in the current locale" do
    money = Reports::Money.new(cents: 123_456, currency: "EUR")

    assert_equal "€1,234.56", I18n.with_locale(:en) { money.to_s }
    assert_equal "1.234,56 €", I18n.with_locale(:it) { money.to_s }
  end

  test "shows the decimals its currency has, and a code it has no symbol for as itself" do
    assert_equal "¥1,200", Reports::Money.new(cents: 120_000, currency: "JPY").to_s
    assert_equal "€12.50", Reports::Money.new(cents: 1250, currency: "EUR").to_s
    assert_equal "SEK12.50", Reports::Money.new(cents: 1250, currency: "SEK").to_s
  end
end
