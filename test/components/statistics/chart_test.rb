# frozen_string_literal: true

require "test_helper"

# A chart's hidden table: the same numbers as the canvas, each formatted as
# its chart's figures are, and an empty chart's message instead of an axis.
class Components::Statistics::ChartTest < ActiveSupport::TestCase
  test "a money chart's table shows each amount in the chart's currency, and a missing one as a dash" do
    chart = Reports::Chart.new(kind: :bar, title: "Spent", labels: %w[Jan Feb], format: :money, currency: "EUR",
                               series: [ Reports::Chart::Series.new(label: "Groceries", values: [ 12.5, nil ]) ])

    cells = render(chart).css("tbody td").map { _1.text.squish }

    assert_equal [ Reports::Money.new(cents: 1250, currency: "EUR").to_s, Statistics::Format.value(nil, :count) ], cells
  end

  test "its table heads a column per series, and leaves the corner over the rows' names a plain cell" do
    chart = Reports::Chart.new(kind: :bar, title: "Spent", labels: %w[Jan], format: :money, currency: "EUR",
                               series: [ Reports::Chart::Series.new(label: "Groceries", values: [ 1 ]) ])

    head = render(chart).at_css("thead tr")

    assert_equal [ "td" ], head.css("td").map(&:name)
    assert_equal [ "Groceries" ], head.css("th[scope=col]").map(&:text)
  end

  test "an empty chart says so instead of drawing an empty axis" do
    chart = Reports::Chart.new(kind: :bar, title: "Spent", labels: %w[Jan], series: [ Reports::Chart::Series.new(label: "s", values: [ 0 ]) ])

    page = render(chart, empty_message: "Nothing spent")

    assert_nil page.at_css("canvas")
    assert_includes page.text, "Nothing spent"
  end

  private

  def render(chart, **) = Nokogiri::HTML5.fragment(Components::Statistics::Chart.new(chart: chart, **).call)
end
