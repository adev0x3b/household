# frozen_string_literal: true

require "test_helper"

class CollectionTest < ActiveSupport::TestCase
  test "belongs to a profile, needs a name and a known section" do
    collection = collections(:b12)
    assert_equal profiles(:alice), collection.profile
    assert_equal "healthcare", collection.section

    assert_not Collection.new(profile: profiles(:alice), section: "healthcare").valid?
    assert_not Collection.new(profile: profiles(:alice), name: "x", section: "bogus").valid?
    assert_predicate Collection.new(profile: profiles(:alice), name: "Job hunt", section: "agenda"), :valid?
  end

  test "status enum values, active by default" do
    assert_equal({ "active" => 0, "paused" => 1, "completed" => 2 }, Collection.statuses)
    assert_equal "active", Collection.new.status
  end

  test "destroying a collection lets its series and purchases go on, and destroys its shares" do
    collection = collections(:b12)
    event = events(:prescription)
    purchase = supply_purchase!(profile: profiles(:alice), name: "Needles", collection: collection)
    share = collection_shares(:b12_bob)

    collection.destroy!

    assert_nil event.reload.collection
    assert_nil purchase.reload.collection
    assert_not CollectionShare.exists?(share.id)
  end

  test "accessible_by: owned, or shared with the profile" do
    assert_includes Collection.accessible_by(profiles(:alice)), collections(:b12)
    assert_includes Collection.accessible_by(profiles(:bob)), collections(:b12)
    assert_not_includes Collection.accessible_by(profiles(:carol)), collections(:b12)
    assert_equal [ collections(:b12) ], Collection.accessible_by(profiles(:alice)).in_section(:healthcare).to_a
  end

  test "a series is offered its section's collections by name, and keeps the one it is in" do
    alice = profiles(:alice)
    job_hunt = Collection.create!(profile: alice, name: "Job hunt", section: "agenda")
    applying = Collection.create!(profile: alice, name: "Applying", section: "agenda")

    assert_equal [ applying, job_hunt ], Collection.choices_for(alice, section: :agenda).to_a
    assert_equal [ applying, collections(:b12), job_hunt ], Collection.choices_for(alice, section: :agenda, current_id: collections(:b12).id).to_a,
                 "a visit moved to Agenda keeps its therapy"
  end

  test "a series in a collection the person can't reach is offered nothing" do
    assert_nil Collection.choices_for(profiles(:carol), section: :healthcare, current_id: collections(:b12).id)
  end
end
