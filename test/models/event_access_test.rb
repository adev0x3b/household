# frozen_string_literal: true

require "test_helper"

# Who sees a series (Event.accessible_by) and which section it belongs to
# (Event.in_section).
class EventAccessTest < ActiveSupport::TestCase
  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
  end

  test "the owner sees their series, a stranger doesn't" do
    assert_includes Event.accessible_by(@alice), events(:groceries)
    assert_not_includes Event.accessible_by(@carol), events(:groceries)
  end

  test "a share on the series lets the other in" do
    events(:groceries).event_shares.create!(profile: @bob)
    assert_includes Event.accessible_by(@bob), events(:groceries)
  end

  test "a share on the collection is a live grant to every series in it" do
    assert_includes Event.accessible_by(@bob), events(:prescription)
    assert_not_includes Event.accessible_by(@carol), events(:prescription)

    collection_shares(:b12_bob).destroy!
    assert_not_includes Event.accessible_by(@bob), events(:prescription)
  end

  test "a link grant opens one kind of the grantor's series" do
    link!(@alice, @bob)
    assert_includes Event.accessible_by(@bob), events(:groceries)
    assert_includes Event.accessible_by(@bob), events(:endocrinologist)

    grant(@alice, @bob, "Task", read: :off)
    assert_not_includes Event.accessible_by(@bob), events(:groceries)
    assert_includes Event.accessible_by(@bob), events(:endocrinologist)
  end

  test "a payment's counterparty reads it" do
    paid = transfer!(payer: @alice, counterparty: @bob, date: Date.new(2026, 3, 2), cents: 1500)

    assert_includes Event.accessible_by(@bob), paid.event
    assert_not_includes Event.accessible_by(@carol), paid.event
    assert_equal [ @alice, @bob ], paid.event.audience
  end

  test "whoever a series' collection is shared with is in its audience, alone or in a batch" do
    series = events(:prescription)
    series.collection.collection_shares.create!(profile: @carol)

    assert_includes series.audience, @carol
    assert_includes Event.audience_of([ series ]), @carol
    assert_not_includes events(:groceries).audience, @carol
  end

  test "one row per series however many ways in, in any order" do
    link!(@alice, @bob)
    events(:prescription).event_shares.create!(profile: @bob)
    seen = Event.accessible_by(@bob).where(id: events(:prescription).id)

    assert_equal 1, seen.count
    assert_equal [ events(:prescription) ], seen.order(Arel.sql("COALESCE(events.start_time, '00:00')")).to_a
  end

  test "what two people see, merged, is what both see" do
    events(:groceries).event_shares.create!(profile: @bob)
    both = Event.accessible_by(@bob).merge(Event.accessible_by(@alice))

    assert_includes both, events(:groceries)
    assert_not_includes both, events(:water_the_plants), "Alice's own, never shared with Bob"
  end

  test "in_section composes the kinds that belong whole and the appointments by kind" do
    interview = appointment!(profile: @alice, date: Date.new(2026, 3, 5), kind: :work, counterpart: "ACME").event

    agenda = Event.in_section(:agenda)
    assert_includes agenda, events(:groceries)
    assert_includes agenda, interview
    assert_not_includes agenda, events(:endocrinologist), "a medical appointment is healthcare"

    healthcare = Event.in_section(:healthcare)
    assert_includes healthcare, events(:endocrinologist)
    assert_includes healthcare, events(:methotrexate)
    assert_includes healthcare, events(:bloodwork)
    assert_not_includes healthcare, interview

    assert_includes Event.in_section(:finance), events(:electricity_bill)
    assert_empty Event.in_section(:nowhere)
  end
end
