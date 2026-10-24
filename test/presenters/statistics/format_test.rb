# frozen_string_literal: true

require "test_helper"

# How a statistic reads: its value in the reader's language, and its
# change against the period before as a difference.
class Statistics::FormatTest < ActiveSupport::TestCase
  Format = Statistics::Format

  test "a number reads as the language writes it, without trailing zeros" do
    assert_equal "200", Format.value(200.0, :number)
    assert_equal "4.5", Format.value(4.5, :number)
    assert_equal "0.75", Format.value(BigDecimal("0.750"), :number)
    I18n.with_locale(:it) { assert_equal "4,5", Format.value(4.5, :number) }
  end

  test "a change is a difference: points for a rate, the count or the amount otherwise" do
    assert_equal "−10 points", Format.delta(metric(70.0, 80.0, :percent))
    assert_equal "+5", Format.delta(metric(8, 3, :count))
    assert_equal "−€30.00", Format.delta(metric(money(70_00), money(100_00), :money))
    assert_equal "No change", Format.delta(metric(3, 3, :count))
    assert_nil Format.delta(metric(3, nil, :count))
  end

  private

  def metric(value, previous, format) = Reports::Metric.new(value: value, previous: previous, format: format, polarity: :neutral)

  def money(cents) = Reports::Money.new(cents: cents, currency: "EUR")
end
