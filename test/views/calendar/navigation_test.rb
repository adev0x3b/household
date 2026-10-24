# frozen_string_literal: true

require "test_helper"

class Views::Calendar::NavigationTest < ActiveSupport::TestCase
  test "the month picker names every month in the reader's language, the shown one picked" do
    picker = render_at(Date.new(2026, 3, 1))

    assert_equal %w[January February March], picker.css("select[name=month] option").first(3).map(&:text)
    assert_equal "3", picker.at_css("select[name=month] option[selected]")["value"]
    assert_equal "2026", picker.at_css("select[name=year] option[selected]")["value"]
    italian = I18n.with_locale(:it) { render_at(Date.new(2026, 3, 1)) }
    assert_equal "Gennaio", italian.at_css("select[name=month] option").text
  end

  private

  def render_at(date)
    component = Views::Calendar::Navigation.new(date: date)
    Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
  end
end
