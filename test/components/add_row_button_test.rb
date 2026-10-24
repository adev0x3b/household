# frozen_string_literal: true

require "test_helper"

class Components::AddRowButtonTest < ActiveSupport::TestCase
  test "it asks the form's rows for a new one, beside a word for what it adds" do
    button = parse(Components::AddRowButton.new(label: "Add a step")).at_css("button.add-row-button")

    assert_equal [ "button", "click->nested-fields#add" ], [ button["type"], button["data-action"] ]
    assert_equal "Add a step", button.at_css("span").text
    assert_equal "true", button.at_css("i.fa-plus")["aria-hidden"]
  end

  test "given a link it opens the form that adds the row" do
    link = parse(Components::AddRowButton.new(label: "Add a range", href: "/reference_ranges/new", data: { turbo_stream: true })).at_css("a")

    assert_equal [ "add-row-button", "/reference_ranges/new" ], [ link["class"], link["href"] ]
    assert link.has_attribute?("data-turbo-stream")
    assert_nil link["data-action"]
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call)
end
