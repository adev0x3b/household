# frozen_string_literal: true

require "test_helper"

# The page's one menu of every kind a day's "+" opens.
class Views::Calendar::AddMenuTest < ActiveSupport::TestCase
  test "it offers every kind, each opening that kind's form in a modal, in its section's colour" do
    menu = parse(Views::Calendar::AddMenu.new).at_css("#day_add_menu")
    form = menu.at_css("form")
    options = form.css("button[type=submit]")
    routes = Rails.application.routes.url_helpers

    assert_equal "get", form["method"]
    assert form.has_attribute?("data-turbo-stream"), "the kind's form opens in a modal"
    assert_equal(Event.types.map { routes.public_send("new_#{_1.route_key}_path") }, options.map { _1["formaction"] })
    assert_equal(Event.types.map { "section--#{_1.starting_section}" }, options.map { _1["class"][/section--\w+/] })
    assert_includes options.find { _1["formaction"] == "/appointments/new" }["class"], "section--healthcare", "a new appointment starts as a visit"
    assert_equal [ "group", I18n.t("calendar.day_card.add_event") ], [ menu["role"], menu["aria-label"] ]
  end

  test "the day pressed is its form's one field, filled when it opens" do
    field = parse(Views::Calendar::AddMenu.new).at_css("form input")

    assert_equal [ "hidden", "date", "date" ], [ field["type"], field["name"], field["data-day-add-target"] ]
  end

  private

  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
end
