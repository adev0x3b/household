# frozen_string_literal: true

require "test_helper"

# Why a form didn't save, above its fields.
class Components::ErrorSummaryTest < ActiveSupport::TestCase
  test "it says nothing was saved and lists what went wrong, as an alert that stays" do
    summary = parse(Components::ErrorSummary.new(record: Recipe.new(profile: profiles(:alice)).tap(&:validate)))

    assert_equal "alert", summary.at_css(".notice--critical")["role"]
    assert_equal I18n.t("form.errors.intro"), summary.at_css(".notice p").text
    assert_equal [ "Name can't be blank" ], summary.css(".notice li").map(&:text)
    assert_empty summary.css(".toast, [data-controller]")
  end

  test "a record without errors draws nothing" do
    assert_empty parse(Components::ErrorSummary.new(record: Recipe.new)).children
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
end
