# frozen_string_literal: true

require "test_helper"

# One day of the calendar, as Calendar::Days hands it its days.
class Views::Calendar::DayCardTest < ActiveSupport::TestCase
  setup do
    @carol = profiles(:carol)
    @date = Date.new(2027, 2, 10)
  end

  test "its + opens the page's menu of every kind for its day, and holds no menu of its own" do
    card = parse(@date)
    plus = card.at_css("button.day-card__add-btn")

    assert_equal [ "day-add#open", "2027-02-10" ], [ plus["data-action"], plus["data-day-add-date-param"] ]
    assert_equal [ Views::Calendar::AddMenu::ID, "false" ], [ plus["aria-controls"], plus["aria-expanded"] ]
    assert_nil card.at_css("##{Views::Calendar::AddMenu::ID}")
  end

  test "its day is named in the reader's language" do
    assert_equal "Wed", parse(@date).at_css(".day-card__day-name").text
    assert_equal "mer", I18n.with_locale(:it) { parse(@date) }.at_css(".day-card__day-name").text
  end

  test "its date is the day's heading, read out whole, and its + says which day it adds to" do
    { en: [ "Wednesday, February 10", "Add event on Wednesday, February 10" ],
      it: [ "mercoledì 10 febbraio", "Aggiungi evento per mercoledì 10 febbraio" ] }.each do |locale, (heading, add)|
      card = I18n.with_locale(locale) { parse(@date) }

      assert_equal heading, card.at_css("h2 .is-sr-only").text
      assert card.css("h2 .day-card__day-name, h2 .day-card__number").all? { _1["aria-hidden"] == "true" }, "the short words aren't read twice"
      assert_equal add, card.at_css(".day-card__add-btn")["aria-label"]
    end
  end

  test "what is still to do comes first, urgent before low, doses by their time; what is done comes last" do
    task!(profile: @carol, date: @date, title: "Dust", priority: :low)
    task!(profile: @carol, date: @date, title: "Bins", priority: :urgent, status: :completed)
    day!(series!("Medication", profile: @carol, starts_on: @date, title: "Evening pill", slots: %w[20:00]), date: @date, time: "20:00")
    day!(series!("Medication", profile: @carol, starts_on: @date, title: "Morning pill", slots: %w[08:00]), date: @date, time: "08:00")
    task!(profile: @carol, date: @date, title: "Pay rent", priority: :urgent)

    titles = parse(@date).css(".day-card__body [aria-label^='Mark']").map { _1["aria-label"][/“(.+)”/, 1] }

    assert_equal [ "Pay rent", "Morning pill", "Evening pill", "Dust", "Bins" ], titles
  end

  test "a visit's fee sits in the visit's card, not in a card of its own" do
    visit = appointment!(profile: @carol, date: @date, title: "Dentist")
    Transactions::SetCost.call(visit, date: @date, title: "Dentist", amount: "60", payment_method: "card")

    card = parse(@date)

    assert_equal 1, card.css(".day-card__body > *").size
    assert_includes card.at_css(".day-card__body").text, "Dentist"
    assert card.at_css(".day-card__body .attached-cost"), "the fee, inside the visit's card"
  end

  test "how a day ended is in its circle: a check when done, a cross when cancelled, a skip mark when skipped, nothing while to do" do
    { "Done" => :completed, "Called off" => :cancelled, "Passed over" => :skipped, "To do" => :pending }.each do |title, status|
      task!(profile: @carol, date: @date, title: title, status: status)
    end

    icons = parse(@date).css(".task-card").to_h do |card|
      [ card.at_css(".task-card__title-link").text, card.css(".task-card__toggle i").map { _1["class"] } ]
    end

    assert_equal({ "Done" => [ "fa-solid fa-check" ], "Called off" => [ "fa-solid fa-xmark" ], "Passed over" => [ "fa-solid fa-forward" ], "To do" => [] }, icons)
  end

  test "a circle and a title keep their ids when the card is drawn again done, so the focus can go back to them" do
    laundry = task!(profile: @carol, date: @date, title: "Laundry")
    task!(profile: @carol, date: @date, title: "Dishes")
    before = parse(@date).css(".task-card__toggle").map { _1["id"] }

    laundry.complete!
    after = parse(@date).css(".task-card__toggle").map { _1["id"] }

    assert_equal 2, before.uniq.size
    assert_equal before.sort, after.sort
    assert_includes after, "day-#{laundry.event_id}-2027-02-10-toggle"
    assert parse(@date).at_css("#day-#{laundry.event_id}-2027-02-10-title.task-card__title-link")
  end

  test "each dose of a day has a circle of its own" do
    morning = Occurrence.new(event_id: 7, date: @date, time: "08:30")
    evening = Occurrence.new(event_id: 7, date: @date, time: "20:00")

    assert_equal "day-7-2027-02-10-0830-toggle", Views::Calendar::Cards::Base.dom_id(morning, :toggle)
    assert_equal "day-7-2027-02-10-2000-toggle", Views::Calendar::Cards::Base.dom_id(evening, :toggle)
  end

  test "a linked housemate's cancelled visit and its fee show how they ended, locked" do
    alice = profiles(:alice)
    link!(alice, @carol)
    grant(alice, @carol, "Appointment", write: :off)
    grant(alice, @carol, "Transaction", write: :off)
    visit = appointment!(profile: alice, date: @date, title: "Dentist")
    Transactions::SetCost.call(visit, date: @date, title: "Dentist", amount: "60", payment_method: "card")
    visit.change_status!("cancelled")

    card = parse(@date).at_css(".appointment-card")

    assert card.at_css(".appointment-card__toggle.is-locked i.fa-xmark"), "the visit's circle"
    assert card.at_css(".attached-cost__toggle.is-locked i.fa-xmark"), "its fee, cancelled with it"
    locked = I18n.t("links.cards.locked", name: alice.display_name)
    assert_equal locked, card.at_css(".appointment-card__toggle.is-locked .is-sr-only").text, "why, in words a screen reader reads"
  end

  test "a day still to do carries no status word; a day that ended says how, and only a done one is struck through" do
    task!(profile: @carol, date: @date, title: "To do")
    task!(profile: @carol, date: @date, title: "Under way", status: :in_progress)
    task!(profile: @carol, date: @date, title: "Passed over", status: :skipped)
    task!(profile: @carol, date: @date, title: "Done", status: :completed)

    cards = parse(@date).css(".task-card").to_h { |card| [ card.at_css(".task-card__title-link").text, card ] }

    assert_nil cards.fetch("To do").at_css(".task-card__status")
    assert_equal "In progress", cards.fetch("Under way").at_css(".task-card__status").text
    assert_equal "Skipped", cards.fetch("Passed over").at_css(".task-card__status").text
    assert_includes cards.fetch("Done").classes, "task-card--completed"
    assert_not_includes cards.fetch("Passed over").classes, "task-card--completed"
  end

  test "a task's priority is a pill only when it is pressing" do
    task!(profile: @carol, date: @date, title: "Dust", priority: :medium)
    task!(profile: @carol, date: @date, title: "Pay rent", priority: :high)

    pills = parse(@date).css(".task-card").to_h { |card| [ card.at_css(".task-card__title-link").text, card.at_css(".status-badge")&.text ] }

    assert_equal({ "Pay rent" => "High", "Dust" => nil }, pills)
  end

  test "an expense is told by its sign; an income is the one kind named" do
    expense!(profile: @carol, date: @date, cents: 4200, title: "Vet")
    income!(profile: @carol, date: @date, cents: 150_000, title: "Salary")

    card = parse(@date)

    assert card.at_css(".transaction-card--expense"), "the kind is on the card, for its styles"
    assert_nil card.at_css(".transaction-card--expense .transaction-card__kind")
    assert_equal "Income", card.at_css(".transaction-card--income .transaction-card__kind").text
  end

  test "a dose warns that its supply is low on today's card only" do
    travel_to Time.zone.local(2027, 2, 10, 9)
    needles = supply_purchase!(profile: @carol, name: "Needles", quantity: 10, remaining: 2, threshold: 5).supply
    dose = timed_medication!(profile: @carol, starts_on: @date - 1, times: %w[08:00])
    dose.event.details.supply_uses.create!(supply: needles, quantity: 1)

    assert parse(@date, today: true).at_css(".medication-card__low-stock-icon"), "today's dose"
    assert_nil parse(@date + 1).at_css(".medication-card__low-stock-icon"), "tomorrow's"
    assert_nil parse(@date - 1).at_css(".medication-card__low-stock-icon"), "yesterday's"
  ensure
    travel_back
  end

  test "a home meal the pantry can't cover warns, and the day reads its stock before it is drawn" do
    pantry_ingredient(@carol, "Rice", quantity: 1)
    meal_on(@carol, @date, recipes: [ recipe_with(@carol, "Risotto", [ "Rice", 2, "kg" ]) ])
    meal_on(@carol, @date, recipes: [ recipe_with(@carol, "Rice pudding", [ "Rice", 0.5, "kg" ]) ])
    meal_on(@carol, @date, kind: :eating_out, title: "Trattoria")

    days = Calendar::Days.on(@carol, @date)
    card = assert_no_queries { render(days) }

    warned = card.css(".meal-card").select { _1.at_css(".meal-card__low-stock-icon") }
    assert_equal([ "Risotto" ], warned.map { _1.at_css(".meal-card__title-link").text })
  end

  test "a day with nothing planned says so instead of an empty body" do
    card = parse(@date)

    assert_nil card.at_css(".day-card__body")
    assert_equal "Nothing planned", card.at_css(".day-card__empty").text
  end

  test "a day shown from the month beside is marked and named by its month" do
    card = parse(@date, beside: true).at_css(".day-card")

    assert_includes card.classes, "day-card--beside"
    assert_equal "Feb", card.at_css(".day-card__day-name").text
  end

  test "today's card is marked, for the calendar to scroll to" do
    card = parse(@date, today: true).at_css(".day-card")

    assert_includes card.classes, "day-card--today"
    assert_equal "today", card["data-calendar-today-target"]
  end

  private

  def parse(date, today: false, beside: false) = render(Calendar::Days.on(@carol, date), date: date, today: today, beside: beside)

  def render(days, date: @date, today: false, beside: false)
    component = Views::Calendar::DayCard.new(date: date, occurrences: days, today: today, beside: beside, viewer: @carol)
    Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
  end
end
