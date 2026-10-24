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

  test "it gives the day another status, a button each, sent as a change of the day's status" do
    form = parse(Views::Calendar::CardMenu.new).css("#card_menu form").first
    entries = form.css("button[type=submit]")

    assert_equal [ "post", "patch" ], [ form["method"], form.at_css("input[name=_method]")["value"] ]
    assert_equal(%w[skipped cancelled pending], entries.map { _1["value"] })
    assert(entries.all? { _1["name"] == "status" })
    assert_equal(%w[skipped cancelled pending].map { I18n.t("links.cards.status.#{_1}") }, entries.map { _1.text.strip })
    assert(entries.none? { _1.has_attribute?("data-turbo-confirm") }, "a status can be changed back, so it asks nothing first")
    assert_equal I18n.t("links.cards.ask_status.skipped", name: "%{name}"), entries.first["data-ask-label"]
  end

  test "it deletes this day or the whole series, a button each, asking first" do
    menu = parse(Views::Calendar::CardMenu.new).at_css("#card_menu")
    form = menu.css("form").last
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

  test "a card's more names its day's addresses and says whether its series repeats" do
    weekly_event(profile: @alice, type: "Task", starts_on: @date, title: "Bins")
    task!(profile: @alice, date: @date, title: "Dentist forms")

    buttons = card_buttons(@alice)

    assert_equal "true", buttons.fetch("Bins")["data-card-menu-repeats-param"]
    assert_equal "false", buttons.fetch("Dentist forms")["data-card-menu-repeats-param"]
    bins = buttons.fetch("Bins")
    event = Event.find_by!(title: "Bins")
    assert_equal [ routes.event_day_path(event, @date), routes.event_day_status_path(event, @date) ],
                 attributes(bins, "data-card-menu-delete-url-param", "data-card-menu-status-url-param")
    assert_equal [ "card-menu#open", "card_menu" ], attributes(bins, "data-action", "aria-controls")
    assert(buttons.values.none? { _1.has_attribute?("data-card-menu-delete-owner-param") || _1.has_attribute?("data-card-menu-status-owner-param") },
           "the viewer's own presses ask nobody")
  end

  test "a day still to do is offered skipping and cancelling, a skipped one the other and pending, a done one no status" do
    task!(profile: @alice, date: @date, title: "To do")
    task!(profile: @alice, date: @date, title: "Skipped", status: :skipped)
    task!(profile: @alice, date: @date, title: "Done", status: :completed)

    buttons = card_buttons(@alice)

    assert_equal %w[skipped cancelled], statuses_of(buttons.fetch("To do"))
    assert_equal %w[cancelled pending], statuses_of(buttons.fetch("Skipped"))
    assert_nil statuses_of(buttons.fetch("Done"))
    assert_not buttons.fetch("Done").has_attribute?("data-card-menu-status-url-param")
  end

  test "a linked housemate's card names the owner whose OK each press waits for; one they may not touch has no more" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :ask, delete: :ask)
    grant(@alice, @bob, "Appointment", write: :on, delete: :off)
    grant(@alice, @bob, "Meal", write: :off, delete: :off)
    task!(profile: @alice, date: @date, title: "Bins")
    appointment!(profile: @alice, date: @date, title: "Dentist")
    series!("Meal", profile: @alice, starts_on: @date, title: "Soup")

    buttons = card_buttons(@bob)

    assert_equal [ "Alice", "Alice" ], attributes(buttons.fetch("Bins"), "data-card-menu-delete-owner-param", "data-card-menu-status-owner-param")
    dentist = buttons.fetch("Dentist")
    assert_equal %w[skipped cancelled], statuses_of(dentist)
    assert_equal [ nil, nil ], attributes(dentist, "data-card-menu-delete-url-param", "data-card-menu-status-owner-param")
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

  def statuses_of(button) = button["data-card-menu-statuses-param"]&.then { JSON.parse(_1) }
  def routes = Rails.application.routes.url_helpers
  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
  def attributes(element, *names) = names.map { element[_1] }
end
