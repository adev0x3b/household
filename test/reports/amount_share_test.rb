# frozen_string_literal: true

require "test_helper"

class Reports::AmountShareTest < ActiveSupport::TestCase
  test "lists the parts largest first, each with its share of the whole" do
    parts = Reports::AmountShare.of({ "Rent" => 75_00, "Bus" => 25_00 }, currency: "EUR")

    listed = parts.map { |part| [ part.label, part.money.cents, part.share ] }
    assert_equal [ [ "Rent", 75_00, 75 ], [ "Bus", 25_00, 25 ] ], listed
    assert_equal [ "EUR" ], parts.map { |part| part.money.currency }.uniq
  end

  test "a whole of nothing gives every part a share of zero" do
    assert_equal [ 0 ], Reports::AmountShare.of({ "Rent" => 0 }, currency: "EUR").map(&:share)
  end
end
