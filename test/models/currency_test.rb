# frozen_string_literal: true

require "test_helper"

class CurrencyTest < ActiveSupport::TestCase
  test "a currency without a minor unit has no decimals, and steps by one" do
    yen = Currency.new("JPY")

    assert_equal [ 0, "1", "¥" ], [ yen.decimals, yen.step, yen.symbol ]
  end

  test "any other code has two decimals, and shows as itself without a symbol of its own" do
    krona = Currency.new("SEK")

    assert_equal [ 2, "0.01", "SEK" ], [ krona.decimals, krona.step, krona.symbol ]
    assert_equal "€", Currency.new("EUR").symbol
  end
end
