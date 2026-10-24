# frozen_string_literal: true

require "test_helper"

# What every component shares: a time on the reader's clock, how long ago
# something was, a figure, a quantity a person reads, and a number a field
# holds.
class Components::BaseTest < ActiveSupport::TestCase
  class Ago < Components::Base
    def initialize(time) = @time = time
    def view_template = plain(time_ago(@time).to_s)
  end

  setup { @component = Components::Base.new }

  test "a time is shown on the clock of the zone in scope" do
    time = Time.utc(2026, 10, 4, 22, 30)

    Time.use_zone("Europe/Rome") { assert_equal "00:30", @component.l(time, format: "%H:%M") }
    Time.use_zone("UTC") { assert_equal "22:30", @component.l(time, format: "%H:%M") }
  end

  test "how long ago reads in the reader's language, and an unknown time says nothing" do
    assert_equal "3 minutes ago", render(Ago.new(3.minutes.ago))
    I18n.with_locale(:it) { assert_equal "3 minuti fa", render(Ago.new(3.minutes.ago)) }
    assert_equal "", render(Ago.new(nil))
  end

  test "a figure reads as the statistics write it, and a missing one as no data" do
    assert_equal "72%", @component.format_figure(72, :percent)
    I18n.with_locale(:it) { assert_equal "1.234", @component.format_figure(1234, :count) }
    assert_equal I18n.t("statistics.no_data"), @component.format_figure(nil, :count)
  end

  test "a quantity reads without trailing zeros, in the language's own decimals" do
    assert_equal "75 mcg", @component.quantity_with_unit(BigDecimal("75.0"), "mcg")
    assert_equal "1.5 kg", @component.quantity_with_unit(1.5, "kg")
    I18n.with_locale(:it) { assert_equal "1,5 kg", @component.quantity_with_unit(1.5, "kg") }
    assert_equal "3", @component.quantity_with_unit(3, nil)
  end

  test "a select's options are worded by the block and sent as their keys" do
    options = @component.select_options(%w[low high]) { |key| I18n.t("tasks.priority.#{key}") }

    assert_equal [ [ I18n.t("tasks.priority.low"), "low" ], [ I18n.t("tasks.priority.high"), "high" ] ], options
  end

  test "a number in a field has no trailing zeros, and a dot in every language" do
    assert_equal "400", @component.number_value(BigDecimal("400.0"))
    assert_equal "0.25", @component.number_value(BigDecimal("0.25"))
    I18n.with_locale(:it) { assert_equal "1.5", @component.number_value(1.5) }
    assert_nil @component.number_value(nil)
  end

  private

  def render(component) = ApplicationController.render(component, layout: false)
end
