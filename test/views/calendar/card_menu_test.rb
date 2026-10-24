# frozen_string_literal: true

require "test_helper"

# The page's one "more" menu of calendar cards, and what each card's
# button tells it.
class Views::Calendar::CardMenuTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @date = Date.new(2027, 2, 10)
  end

  test "it deletes this day or the whole series, a button each, asking first" do
    menu = parse(Views::Calendar::CardMenu.new).at_css("#card_menu")
    form = menu.at_css("form")
    entries = form.css("button[type=submit]")

    assert_equal [ "group", I18n.t("links.cards.more") ], [ menu["role"], menu["aria-label"] ]
    assert_equal [ "post", "delete" ], [ form["method"], form.at_css("input[name=_method]")["value"] ]
    assert_equal(%w[occurrence series], entries.map { _1["value"] })
    assert(entries.all? { _1["name"] == "scope" })
    assert_equal([ I18n.t("links.cards.delete_occurrence"), I18n.t("links.cards.delete_series") ], entries.map { _1.text.strip })
    assert_equal([ I18n.t("links.cards.delete_occurrence_confirm"), I18n.t("links.cards.delete_series_confirm") ],
                 entries.map { _1["data-turbo-confirm"] })
  end

  test "each delete carries the request's words too, the owner's name left for the controller to fill" do
    series = parse(Views::Calendar::CardMenu.new).at_css("button[value=series]")

    assert_equal I18n.t("links.cards.ask_delete_series", name: "%{name}"), series["data-ask-label"]
    assert_equal I18n.t("links.cards.ask_delete_series_confirm", name: "%{name}"), series["data-ask-confirm"]
    assert_includes series["data-ask-label"], "%{name}"
  end

  test "a card's more names its day and says whether its series repeats" do
    weekly_event(profile: @alice, type: "Task", starts_on: @date, title: "Bins")
    task!(profile: @alice, date: @date, title: "Dentist forms")

    buttons = card_buttons(@alice)

    assert_equal "true", buttons.fetch("Bins")["data-card-menu-repeats-param"]
    assert_equal "false", buttons.fetch("Dentist forms")["data-card-menu-repeats-param"]
    bins = buttons.fetch("Bins")
    assert_equal Rails.application.routes.url_helpers.event_day_path(Event.find_by!(title: "Bins"), @date), bins["data-card-menu-url-param"]
    assert_equal [ "card-menu#open", "card_menu" ], attributes(bins, "data-action", "aria-controls")
    assert(buttons.values.none? { _1.has_attribute?("data-card-menu-owner-param") }, "the viewer's own deletes ask nobody")
  end

  test "a linked housemate's card names the owner whose OK its delete waits for; one not to delete has no more" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", delete: :ask)
    grant(@alice, @bob, "Meal", delete: :off)
    task!(profile: @alice, date: @date, title: "Bins")
    series!("Meal", profile: @alice, starts_on: @date, title: "Soup")

    buttons = card_buttons(@bob)

    assert_equal "Alice", buttons.fetch("Bins")["data-card-menu-owner-param"]
    assert_not buttons.key?("Soup")
  end

  private

  # Each card's "more" button, by its title.
  def card_buttons(viewer)
    day = Views::Calendar::DayCard.new(date: @date, occurrences: Calendar::Days.on(viewer, @date), viewer: viewer)
    parse(day).css(".day-card__body > *").filter_map do |card|
      button = card.at_css(".card-actions .item-menu__button") or next
      [ card.at_css("[class$='__title-link'], [class$='__name-link']").text, button ]
    end.to_h
  end

  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
  def attributes(element, *names) = names.map { element[_1] }
end
