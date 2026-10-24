# frozen_string_literal: true

require "test_helper"

# A dashboard's period: a button naming it, opening the shortcuts and two
# dates to apply.
class Components::Statistics::PeriodSelectorTest < ActiveSupport::TestCase
  test "the button names the shortcut the period is, and each shortcut opens its period with the page's other filters" do
    travel_to Date.new(2026, 10, 19) do
      selector = parse(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31), params: { member: "7" })
      shortcuts = selector.css("a.stat-period-selector__shortcut")

      assert_equal "dropdown", selector.at_css(".stat-period-selector")["data-controller"]
      button = selector.at_css("button[data-dropdown-target=toggler][aria-expanded=false]")
      assert_equal [ "Period", "Current month" ], button.css("span").map(&:text)
      assert_equal %w[Last\ 30\ days Current\ month Previous\ month Next\ month Current\ year], shortcuts.map(&:text)
      assert(shortcuts.all? { _1["data-turbo-action"] == "replace" && _1["data-action"] == "click->dropdown#close" })
      assert_includes shortcuts.map { _1["href"] }, "/home/finance?end_date=2026-09-30&member=7&start_date=2026-09-01"
      assert_equal [ "Current month" ], shortcuts.select { _1["aria-current"] == "true" && _1["class"].include?("is-current") }.map(&:text)
    end
  end

  test "a period of one's own is named by its dates, with the year only when it isn't this one, and the form keeps the other filters" do
    travel_to Date.new(2026, 10, 19) do
      selector = parse(start_date: Date.new(2026, 3, 2), end_date: Date.new(2026, 4, 5), params: { member: "7" })
      assert_equal "Mar 2 – Apr 5", selector.at_css(".stat-period-selector__name").text

      selector = parse(start_date: Date.new(2025, 12, 1), end_date: Date.new(2026, 1, 31))
      assert_equal "December 1, 2025 – January 31, 2026", selector.at_css(".stat-period-selector__name").text

      form = parse(start_date: Date.new(2026, 3, 2), end_date: Date.new(2026, 4, 5), params: { member: "7" }).at_css("form.stat-period-selector__custom")
      assert_equal [ "/home/finance", "replace", "submit->dropdown#close" ], [ form["action"], form["data-turbo-action"], form["data-action"] ]
      assert_equal "7", form.at_css("input[type=hidden][name=member]")["value"]
      assert_equal %w[2026-03-02 2026-04-05], dates_of(form)
      assert_equal "Apply", form.at_css("button[type=submit]").text
    end
  end

  private

  def dates_of(form) = form.css("label.stat-period-selector__field input[type=date]").map { _1["value"] }

  def parse(**dates)
    selector = Components::Statistics::PeriodSelector.new(url: "/home/finance", **dates)
    Nokogiri::HTML5.fragment(ApplicationController.render(selector, layout: false))
  end
end
