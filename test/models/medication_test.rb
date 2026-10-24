# frozen_string_literal: true

require "test_helper"

class MedicationTest < ActiveSupport::TestCase
  test "requires a title and a kind" do
    medication = Medication.new(profile: profiles(:alice), starts_on: Date.current)
    assert_not medication.valid?
    assert_includes medication.errors[:title], "can't be blank"
    assert_predicate medication.errors["details.kind"], :any?
  end

  test "does not require a quantity" do
    medication = Medication.new(profile: profiles(:alice), starts_on: Date.current, title: "Test", details_attributes: { kind: :pill })
    assert_predicate medication, :valid?
  end

  test "requires area and side when kind is injection, not for a pill or drops" do
    injection = Medication.new(profile: profiles(:alice), starts_on: Date.current, title: "Test", details_attributes: { kind: :injection })
    assert_not injection.valid?
    assert_predicate injection.errors["details.area"], :any?
    assert_predicate injection.errors["details.side"], :any?

    assert_predicate Medication.new(profile: profiles(:alice), starts_on: Date.current, title: "Test", details_attributes: { kind: :pill }), :valid?
    assert_predicate Medication.new(profile: profiles(:alice), starts_on: Date.current, title: "Test", details_attributes: { kind: :drops }), :valid?
  end

  test "an override row may leave everything blank" do
    day = occurrences(:methotrexate_due)
    override = day.override_details
    assert_predicate override, :valid?
    assert_equal "left", override.side, "reads the series until set"
  end

  test "kinds, areas and sides keep their stored numbers; a dose is skipped for one of its reasons" do
    assert_equal({ "injection" => 0, "pill" => 1, "drops" => 2 }, Medication::Details.kinds)
    assert_equal({ "thigh" => 0, "glute" => 1, "arm" => 2 }, Medication::Details.areas)
    assert_equal({ "left" => 0, "right" => 1 }, Medication::Details.sides)
    assert_equal %w[refused not_available held forgot other], Medication.skip_reasons
  end

  test "a side's opposite is the other one" do
    assert_equal :right, Medication::Details.opposite_side(:left)
    assert_equal :left, Medication::Details.opposite_side("right")
  end

  test "a one-off's dose goes on the series' side" do
    event = events(:methotrexate)
    assert_not event.recurring?
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 2))).to_s
  end

  test "a repeating injection alternates sides from its first dose" do
    event = events(:cobalamin)
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 2))).to_s
    assert_equal "right", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 9))).to_s
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 16))).to_s
    assert_equal "right", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 23))).to_s
  end

  test "several doses a day alternate dose by dose, and a dose taken in one tap keeps its side" do
    event = events(:cobalamin)
    event.update!(rrule: "FREQ=DAILY", event_slots: EventSlot.rows_for(%w[08:00 20:00]))
    event.details.update!(area: :glute)

    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 2), time: "08:00")).to_s
    assert_equal "right", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 2), time: "20:00")).to_s
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 3), time: "08:00")).to_s
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 3))).to_s, "no time: the day's first dose"

    evening = event.occurrence_on(Date.new(2026, 3, 3), time: "20:00")
    evening.complete!
    assert_equal "right", evening.details.side
    assert_equal "right", evening.own_details.own_side, "written on the day alone"

    morning = event.occurrence_on(Date.new(2026, 3, 3), time: "08:00")
    morning.complete!
    assert_nil morning.own_details, "the series' side needs no override"
  end

  test "a series whose doses are all ahead takes a new rule or new slots in place, and the alternation follows" do
    travel_to Time.zone.local(2026, 3, 1, 12)
    event = events(:cobalamin)
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 16))).to_s, "weekly: the third dose"

    assert_equal event, Events::Reschedule.call(event, rrule: "FREQ=DAILY;INTERVAL=2").series
    assert_equal "right", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 16))).to_s, "every other day: the eighth dose"

    Events::Reschedule.call(event, rrule: event.rrule, slots: %w[08:00 20:00])
    assert_equal "left", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 16), time: "08:00")).to_s, "the fifteenth dose"
    assert_equal "right", event.projected_side_for(event.occurrence_on(Date.new(2026, 3, 16), time: "20:00")).to_s, "the sixteenth dose"
  end

  test "a series with doses behind it goes on as a new one, on the side the old one would have reached" do
    travel_to Time.zone.local(2026, 3, 10, 12)
    event = events(:cobalamin)
    event.occurrence_on(Date.new(2026, 3, 2)).complete!
    event.occurrence_on(Date.new(2026, 3, 9)).complete!

    continued = Events::Reschedule.call(event, rrule: "FREQ=DAILY").series

    assert_not_equal event, continued
    assert_equal [ Date.new(2026, 3, 10), "left" ], [ continued.starts_on, continued.details.side ], "the third dose"
    assert_equal "right", continued.projected_side_for(continued.occurrence_on(Date.new(2026, 3, 11))).to_s
    assert_equal [ "left", "right" ], event.occurrences.completed.order(:date).map { |dose| dose.details.side.to_s }, "the doses taken keep theirs"
  end

  test "a taken dose draws what the series plans to use, an untaken one gives it back" do
    alice = profiles(:alice)
    purchase = supply_purchase!(profile: alice, name: "Needles", quantity: 10)
    event = events(:cobalamin)
    event.details.supply_uses.create!(supply: purchase.supply, quantity: 2)

    dose = event.occurrence_on(Date.new(2026, 3, 9))
    dose.complete!
    assert_equal 8, purchase.reload.quantity_remaining
    assert_equal([ [ purchase.supply_id, 2 ] ], dose.supply_consumptions.map { |c| [ c.supply_id, c.quantity.to_i ] })

    dose.complete!
    assert_equal 8, purchase.reload.quantity_remaining, "taking it again draws nothing more"

    dose.uncomplete!
    assert_equal 10, purchase.reload.quantity_remaining
    assert_empty dose.supply_consumptions.reload
  end

  test "a dose's own uses replace the series' for that day" do
    alice = profiles(:alice)
    needles = supply_purchase!(profile: alice, name: "Needles", quantity: 10)
    swabs = supply_purchase!(profile: alice, name: "Swabs", quantity: 10)
    event = events(:cobalamin)
    event.details.supply_uses.create!(supply: needles.supply, quantity: 1)

    dose = event.occurrence_on(Date.new(2026, 3, 9))
    dose.complete!
    event.replace_uses_for!(dose, [ [ swabs.supply_id, "3" ] ])

    assert_equal 10, needles.reload.quantity_remaining, "what the old list drew came back"
    assert_equal 7, swabs.reload.quantity_remaining
    assert_equal [ [ swabs.supply_id, "3.0" ] ], dose.reload.details.uses_list
    assert_equal [ [ needles.supply_id, "1.0" ] ], event.occurrence_on(Date.new(2026, 3, 16)).details.uses_list, "the other days keep the series' list"
  end

  test "deleting a taken dose gives its stock back" do
    purchase = supply_purchase!(profile: profiles(:alice), name: "Needles", quantity: 10)
    event = events(:cobalamin)
    event.details.supply_uses.create!(supply: purchase.supply, quantity: 2)
    dose = event.occurrence_on(Date.new(2026, 3, 9)).tap(&:complete!)

    event.on_occurrences_destroying([ dose ])
    assert_equal 10, purchase.reload.quantity_remaining
  end

  test "a dose is low on supplies when one it uses is under its threshold" do
    needles = supply_purchase!(profile: profiles(:carol), name: "Needles", quantity: 10, remaining: 2, threshold: 5).supply
    wipes = supply_purchase!(profile: profiles(:carol), name: "Wipes", quantity: 50, remaining: 40, threshold: 5).supply
    dose = timed_medication!(profile: profiles(:carol), starts_on: Date.new(2027, 2, 10), times: %w[08:00])
    details = dose.event.details

    details.supply_uses.create!(supply: wipes, quantity: 1)
    assert_not_predicate details, :low_on_supplies?

    details.supply_uses.create!(supply: needles, quantity: 1)
    assert_predicate details.reload, :low_on_supplies?
  end
end
