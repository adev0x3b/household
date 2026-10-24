# frozen_string_literal: true

require "test_helper"

# Collections are a few series shared as one thing: therapies in
# Healthcare, worded per section elsewhere.
class CollectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob) # Alice's B12 collection is shared with him
    sign_in @alice
  end

  test "the index is Healthcare's therapies unless another section is asked for" do
    job_hunt = Collection.create!(profile: @alice, name: "Job hunt", section: "agenda")

    get collections_path
    assert_response :success
    assert_select "h1", text: "Medical therapies"
    assert_select "#collection_#{collections(:b12).id}", text: /B12/
    assert_select "#collection_#{job_hunt.id}", 0
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_collection_path(section: "healthcare")

    get collections_path(section: "agenda")
    assert_select "h1", text: "Agenda collections"
    assert_select "#collection_#{job_hunt.id}", text: /Job hunt/
    assert_select "#collection_#{collections(:b12).id}", 0
    assert_select "input[type=hidden][name=section][value=agenda]"
  end

  test "the index lists what is shared with you, not what isn't" do
    sign_in @bob

    get collections_path

    assert_select "#collection_#{collections(:b12).id}", text: /B12/
    assert_select "#collection_#{collections(:fibromyalgia).id}", text: /Fibromyalgia/
    assert_select "#collection_#{collections(:b12).id} a[href=?]", new_collection_share_path(collection_id: collections(:b12).id), 0
  end

  test "a new collection goes in the section it was made from, worded by it" do
    get new_collection_path(section: "agenda"), as: :turbo_stream
    assert_select "input[type=hidden][name='collection[section]'][value=agenda]"
    assert_select ".modal__header", text: /New collection/

    assert_difference -> { @alice.collections.count }, 1 do
      post collections_path, params: { collection: { name: "Moving house", notes: "Boxes", section: "agenda" } },
                             headers: submitted_from(collections_path(section: "agenda"))
    end
    moving = Collection.find_by!(name: "Moving house")
    assert_equal "agenda", moving.section
    assert_equal "Boxes", moving.notes
    assert_redirected_to collections_path(section: "agenda")
    follow_redirect!
    assert_toast "Collection added."
    assert_select "#collection_#{moving.id}"
  end

  test "a therapy by default, and a name is required" do
    post collections_path, params: { collection: { name: "Physiotherapy" } }, headers: submitted_from(collections_path)
    assert_equal "healthcare", Collection.find_by!(name: "Physiotherapy").section
    follow_redirect!
    assert_toast "Therapy added."

    assert_no_difference "Collection.count" do
      post collections_path, as: :turbo_stream, params: { collection: { name: "" } }
    end
    assert_includes response.body, "turbo-stream"
  end

  test "its page lists the series in it, each opening its first day" do
    therapy = collections(:b12)
    visit = appointment!(profile: @alice, date: Date.new(2026, 10, 6), collection: therapy, title: "Endocrinologist")
    weekly = series!("Medication", profile: @alice, starts_on: Date.new(2026, 10, 1), title: "Cobalamin", rrule: "FREQ=WEEKLY", collection: therapy)

    get collection_path(therapy)

    assert_response :success
    assert_select ".collection-show.section--healthcare"
    assert_select "a.collection-event-row[href=?]", edit_event_day_path(visit.event, visit.date), text: /Endocrinologist/
    assert_select "a.collection-event-row[href=?]", edit_event_day_path(weekly, "2026-10-01"), text: /Cobalamin/
    assert_select "a.collection-event-row[href=?]", edit_event_day_path(occurrences(:groceries_due).event, occurrences(:groceries_due).date), 0
    assert_select ".page-header a.page-header__back[href=?][aria-label='Back to medical therapies']",
                  collections_path(section: "healthcare")
  end

  test "the one it's shared with may edit it, not delete it" do
    sign_in @bob
    therapy = collections(:b12)

    patch collection_path(therapy), as: :turbo_stream, params: { collection: { name: "B12 2", status: "paused", section: "agenda" } }
    therapy.reload
    assert_equal [ "B12 2", "paused", "healthcare" ], [ therapy.name, therapy.status, therapy.section ], "it stays in its section"

    assert_no_difference "Collection.count" do
      delete collection_path(therapy), as: :turbo_stream
    end
  end

  test "deleting it leaves its series on the calendar" do
    therapy = collections(:b12)
    task = events(:prescription)

    delete collection_path(therapy), as: :turbo_stream

    assert_not Collection.exists?(therapy.id)
    assert_nil task.reload.collection_id
  end

  test "someone else's collection can't be seen" do
    sign_in profiles(:carol)
    get collections_path # a 404 first would drop the test sign-in before its session is saved

    get collection_path(collections(:b12))
    assert_response :not_found
  end
end
