# frozen_string_literal: true

require "test_helper"

# Every lock the code says it takes, shown to be waited for: while another
# connection holds it, the code stops until it is let go. Without the lock,
# two requests at once would both read the same row and both act on it, and
# no test run one after the other would notice.
#
# A lock is only waited for between two connections, and a transactional
# test gives every thread the same one, so these run outside a transaction.
# What each makes is in a household of its own, removed after.
class LocksTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @household = Household.create!(name: "Locks")
    @ann, @ben = %w[Ann Ben].map do |name|
      Profile.create!(household: @household, username: "locks-#{name.downcase}", email: "locks-#{name.downcase}@example.com",
                      first_name: name, password: "a password long enough")
    end
  end

  teardown do
    Households::Destroy.call(@household)
  end

  test "a lock nobody takes is no wait" do
    assert_raises(Minitest::Assertion) { assert_waits_for_lock(@household) { @household.reload } }
  end

  test "inviting someone waits for the household" do
    assert_waits_for_lock(@household) { Households::Invite.call(@household, inviter: @ann, email: "cleo@example.com") }
  end

  test "starting an upload waits for the household" do
    assert_waits_for_lock(@household) { Uploads::Create.call(owner: @ann, name: "notes.txt", byte_size: 5) }
  end

  test "a file's next chunk and its finish wait for the file" do
    upload = Uploads::Create.call(owner: @ann, name: "notes.txt", byte_size: 5).upload

    assert_waits_for_lock(upload) { Uploads::Append.call(upload, io: StringIO.new("hello"), offset: 0, length: 5) }
    assert_waits_for_lock(upload) { Uploads::FinishJob.perform_now(upload) }
  end

  test "a public link's download waits for the link" do
    link, _ = mint_link(keep_file(@ann))

    assert_waits_for_lock(link) { link.consume! }
  end

  test "a press on a day, done or another status, waits for the day" do
    day = task!(profile: @ann, date: Date.current)

    assert_waits_for_lock(day) { Occurrence.find(day.id).mark_completed!(true) }
    assert_waits_for_lock(day) { Occurrence.find(day.id).change_status!("skipped") }
  end

  test "a day saved for the first time waits for its series" do
    plants = series!("Task", profile: @ann, starts_on: Date.current, title: "Water the plants", rrule: "FREQ=DAILY")

    assert_waits_for_lock(plants) { plants.occurrence_on(Date.current + 1).mark_completed!(true) }
  end

  test "reading which days of a series were never saved waits for the series" do
    plants = series!("Task", profile: @ann, starts_on: Date.current, title: "Water the plants", rrule: "FREQ=DAILY")
    plants.advance_unsaved_from!

    assert_waits_for_lock(plants, holding: "FOR SHARE") { Event.find(plants.id).advance_unsaved_from! }
  end

  test "eating a meal waits for its ingredients" do
    pantry_ingredient(@ann, "Flour", quantity: 1)
    pancakes = recipe_with(@ann, "Pancakes", [ "Flour", 200, "g" ])
    meal = meal_on(@ann, Date.current, recipes: [ pancakes ])

    assert_waits_for_lock(Ingredient.find_by!(profile: @ann, name: "Flour")) { Meal::Consumption.new(meal).record! }
  end

  test "ticking an item off a list, or back, waits for the item" do
    list = GroceryList.create!(profile: @ann, name: "Weekly shop")
    item = list.grocery_list_items.create!(ingredient: pantry_ingredient(@ann, "Milk", quantity: 0, unit: "l"), quantity: 1)

    assert_waits_for_lock(item) { GroceryListItem.find(item.id).check! }
    assert_waits_for_lock(item) { GroceryListItem.find(item.id).uncheck! }
  end

  test "answering a housemate's request waits for the request" do
    link!(@ann, @ben)
    approval = Links::Approvals::Hold.call(requester: @ben, record: task!(profile: @ann, date: Date.current), kind: :complete)

    assert_waits_for_lock(approval) { Links::Approvals::Decide.call(LinkApproval.find(approval.id), approve: true) }
  end

  test "applying the assistant's changes waits for the change set" do
    appointment!(profile: @ann, date: Date.current)
    asked = submit_changes(assistant_chat(@ann), [ { intent: 0, op: "delete", type: "appointment", fields: { all: true } } ])
    set = Assistant::ChangeSet.find(asked[:data][:change_set_id])
    assert_predicate set, :awaiting_confirmation?

    assert_waits_for_lock(set) { Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(set.id), confirmed: true) }
  end

  test "a new setup code waits for whoever is making the first account" do
    assert_waits_for_lock(advisory: Admins::Create::FIRST_ACCOUNT_LOCK) { SetupCodes::Renew.call }
  end

  test "the first account waits for whoever is making it already" do
    assert_waits_for_lock(advisory: Admins::Create::FIRST_ACCOUNT_LOCK) do
      Admins::Create.call(household_name: "First", username: "first", email: "first@example.com",
                          password: "a password long enough", first: true)
    end
  end
end
