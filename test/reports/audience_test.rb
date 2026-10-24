# frozen_string_literal: true

require "test_helper"

class Reports::AudienceTest < ActiveSupport::TestCase
  setup do
    @viewer = profiles(:carol)
    @partner = profiles(:bob)
    @stranger = profiles(:alice)
  end

  test "members are the viewer plus owners of series shared with them" do
    shared = series!("Medication", profile: @partner, starts_on: Date.new(2025, 1, 1))
    EventShare.create!(event: shared, profile: @viewer)

    assert_equal [ @partner, @viewer ].sort_by(&:username), audience_for(@viewer).members
  end

  test "a member id the viewer can't reach is ignored instead of widening access" do
    audience = Reports::Audience.new(viewer: @viewer, member_id: @stranger.id)

    assert_not audience.filtered?
    assert_not_includes audience.events.pluck(:profile_id), @stranger.id
  end

  test "filtering by member narrows to that member's series" do
    own = series!("Medication", profile: @viewer, starts_on: Date.new(2025, 1, 1))
    shared = series!("Medication", profile: @partner, starts_on: Date.new(2025, 1, 1))
    EventShare.create!(event: shared, profile: @viewer)

    assert_equal [ shared.id ], audience_for(@viewer, member: @partner).events.pluck(:id)
    assert_equal [ own.id, shared.id ].sort, audience_for(@viewer).events.pluck(:id).sort
  end

  test "a series shared with several people is still one series" do
    event = series!("Transaction", profile: @viewer, starts_on: Date.new(2025, 1, 1))
    EventShare.create!(event: event, profile: @partner)
    EventShare.create!(event: event, profile: @stranger)

    assert_equal 1, audience_for(@viewer).events.count
  end

  test "a payment logged against the viewer is theirs to read, its payer a member" do
    payment = transfer!(payer: @partner, counterparty: @viewer, date: Date.new(2025, 1, 1), cents: 100_00)

    assert_equal [ payment.event_id ], audience_for(@viewer).events.of_type(Transaction).pluck(:id)
    assert_includes audience_for(@viewer).members, @partner
  end

  test "kinds and sections narrow the series, whoever shares them" do
    task = series!("Task", profile: @viewer, starts_on: Date.new(2025, 1, 1))
    visit = appointment!(profile: @viewer, date: Date.new(2025, 1, 2), kind: :medical).event
    dinner = appointment!(profile: @viewer, date: Date.new(2025, 1, 3), kind: :social).event
    audience = audience_for(@viewer)

    assert_equal [ task.id ], audience.events_of_type(Task).pluck(:id)
    assert_equal [ task.id, dinner.id ].sort, audience.events.in_section(:agenda).pluck(:id).sort
    assert_equal [ visit.id ], audience.events.in_section(:healthcare).pluck(:id)
  end

  test "collections are the ones the viewer can access, narrowed by member" do
    own = Collection.create!(profile: @viewer, name: "B12")
    shared = Collection.create!(profile: @partner, name: "Physio")
    CollectionShare.create!(collection: shared, profile: @viewer)
    Collection.create!(profile: @stranger, name: "Private")

    assert_equal [ own, shared ].sort_by(&:id), audience_for(@viewer).collections.order(:id).to_a
    assert_equal [ own ], audience_for(@viewer, member: @viewer).collections.to_a
  end
end
