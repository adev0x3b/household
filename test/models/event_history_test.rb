# frozen_string_literal: true

require "test_helper"

# A done day is a record of what was done: editing a repeating series
# changes what is still to come, never what happened.
class EventHistoryTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
  end

  def rent
    series!("Transaction", profile: @alice, starts_on: Date.new(2026, 1, 5), title: "Rent", rrule: "FREQ=MONTHLY",
                           kind: :expense, category: :housing, amount_cents: 80_000, currency: "EUR", payment_method: :bank_transfer)
  end

  test "a repeating payment's paid months keep their amount and name when the series changes" do
    event = rent
    january = day!(event, date: Date.new(2026, 1, 5), status: :completed)
    february = day!(event, date: Date.new(2026, 2, 5), status: :completed).tap { |day| day.write_details!(amount_cents: 85_000) }
    march = day!(event, date: Date.new(2026, 3, 5))

    event.update!(title: "Rent, new flat")
    event.details.update!(amount_cents: 90_000, payment_method: :card)

    assert_equal([ 80_000, 85_000, 90_000 ], [ january, february, march ].map { |day| day.reload.details.amount_cents })
    assert_equal(%w[bank_transfer bank_transfer card], [ january, february, march ].map { |day| day.reload.details.payment_method })
    assert_equal([ "Rent", "Rent", "Rent, new flat" ], [ january, february, march ].map { |day| day.reload.title })
    assert_equal 90_000, event.occurrence_on(Date.new(2026, 4, 5)).details.amount_cents, "the months to come follow the series"
    assert_equal "housing", january.details.category, "what didn't change is still read from the series"
    assert_nil january.own_details.own_category
  end

  test "reading the series again changes nothing more on its done days" do
    event = rent
    january = day!(event, date: Date.new(2026, 1, 5), status: :completed)
    event.details.update!(amount_cents: 90_000)

    assert_no_difference -> { Transaction::Details.count } do
      event.details.update!(amount_cents: 95_000)
    end
    assert_equal 80_000, january.reload.details.amount_cents
  end

  test "a one-off's day is the series: editing it edits the day" do
    visit = series!("Appointment", profile: @alice, starts_on: Date.new(2026, 3, 2), title: "Checkup", kind: :medical, counterpart: "Dr. Rossi")
    day = day!(visit, date: Date.new(2026, 3, 2), status: :completed)

    visit.update!(title: "Annual checkup")
    visit.details.update!(counterpart: "Dr. Bianchi")

    assert_equal "Annual checkup", day.reload.title
    assert_equal "Dr. Bianchi", day.details.counterpart
    assert_nil day.own_details
  end

  test "a taken dose keeps its side and what it planned to use when the plan changes" do
    strips = Supply.create!(profile: @alice, name: "Strips", unit_label: "strip")
    needles = Supply.create!(profile: @alice, name: "Needles", unit_label: "needle")
    event = series!("Medication", profile: @alice, starts_on: Date.new(2026, 3, 2), title: "Insulin", rrule: "FREQ=DAILY",
                                  kind: :injection, area: :thigh, side: :left, quantity: 1, unit: "ml")
    event.details.replace_uses!([ [ strips.id, "1" ] ])
    taken = day!(event, date: Date.new(2026, 3, 2), status: :completed)
    open = day!(event, date: Date.new(2026, 3, 3))

    event.details.update!(side: :right)
    event.details.replace_uses!([ [ needles.id, "2" ] ])

    assert_equal "left", taken.reload.details.side
    assert_equal([ "Strips" ], taken.details.resolved_uses.map { |use| use.supply.name })
    assert_equal "right", open.reload.details.side
    assert_equal([ "Needles" ], open.details.resolved_uses.map { |use| use.supply.name })
  end

  test "an eaten meal keeps its recipes when the plan changes" do
    pizza = Recipe.create!(profile: @alice, name: "Pizza")
    pasta = Recipe.create!(profile: @alice, name: "Pasta")
    event = series!("Meal", profile: @alice, starts_on: Date.new(2026, 3, 6), title: "Friday dinner", rrule: "FREQ=WEEKLY",
                            kind: :home, meal_type: :dinner)
    event.details.meal_recipes.create!(recipe: pizza)
    eaten = day!(event, date: Date.new(2026, 3, 6), status: :completed)

    event.details.update!(meal_recipes_attributes: [ { id: event.details.meal_recipes.first.id, _destroy: "1" }, { recipe_id: pasta.id } ])

    assert_equal [ "Pizza" ], eaten.reload.details.resolved_recipes.map(&:name)
    assert_equal [ "Pasta" ], event.occurrence_on(Date.new(2026, 3, 13)).details.resolved_recipes.map(&:name)
  end

  test "removing a series removes its lists and its days, keeping nothing" do
    strips = Supply.create!(profile: @alice, name: "Strips", unit_label: "strip")
    event = series!("Medication", profile: @alice, starts_on: Date.new(2026, 3, 2), title: "Insulin", rrule: "FREQ=DAILY", kind: :pill)
    event.details.replace_uses!([ [ strips.id, "1" ] ])
    day!(event, date: Date.new(2026, 3, 2), status: :completed)

    assert_difference -> { SupplyUse.count } => -1, -> { Medication::Details.count } => -1 do
      Events::Purge.call([ event ])
    end
  end
end
