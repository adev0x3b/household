# frozen_string_literal: true

require "test_helper"

# The services shared by the kinds' controllers and the assistant: a new
# series, deleting a day or a series, a cost attached to a day.
class OccurrencesServicesTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @carol = profiles(:carol)
    @day = Date.new(2026, 9, 25)
  end

  # --- Occurrences::Create ----------------------------------------------------

  test "create saves the series with its recurrence and drops an inaccessible collection" do
    visit = Appointment.new(title: "Visit", starts_on: @day, details_attributes: { counterpart: "Moretti" })
    Occurrences::Create.call(visit, by: @carol, recurrence: { frequency: "monthly" }, collection_id: collections(:b12).id)

    assert_predicate visit, :persisted?
    assert_equal @carol, visit.profile
    assert_predicate visit, :recurring?
    assert_equal "Moretti", visit.details.counterpart
    assert_nil visit.collection_id, "carol has no access to alice's collection"
    assert_predicate visit.first_occurrence, :projected?, "nothing is stored about its first day yet"

    shared = Appointment.new(title: "Visit", starts_on: @day)
    Occurrences::Create.call(shared, by: @bob, collection_id: collections(:b12).id)
    assert_equal collections(:b12).id, shared.collection_id, "bob has it through a collection share"
  end

  test "create raises on an invalid series and leaves nothing behind" do
    assert_no_difference -> { Event.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        Occurrences::Create.call(Appointment.new(starts_on: @day), by: @alice)
      end
    end
  end

  test "create with slots saves them on the series, and the first dose knows its slot" do
    dose = timed_medication!(profile: @alice, starts_on: @day, times: %w[dinner CV 08:00])
    series = dose.event

    assert_equal [ [ "08:00", nil ], [ "19:30", "CV" ] ], series.slots, "an unknown word is dropped, a repeat too"
    assert_predicate series, :timed?
    assert_equal "08:00", dose.time_string
    assert_nil dose.anchor
    assert_equal [ [ @day, "08:00" ], [ @day, "19:30" ] ], series.occurrences_between(@day, @day).map(&:key)

    anchored = Medication.new(starts_on: @day, title: "Levothyroxine", details_attributes: { kind: :pill })
    Occurrences::Create.call(anchored, by: @alice, recurrence: { slots: %w[CM] })
    assert_not anchored.recurring?
    assert_equal "08:00", anchored.first_occurrence.time_string
    assert_equal "CM", anchored.first_occurrence.anchor
  end

  test "create on a linked housemate's calendar follows their grant" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", create: :off)
    Links::Permissions.reset!

    assert_raises(Pundit::NotAuthorizedError) do
      Occurrences::Create.call(Task.new(profile: @alice, starts_on: @day, title: "x"), by: @bob)
    end
  end

  # --- Occurrences::Destroy ---------------------------------------------------

  test "destroying one dose of a day leaves the day's other dose" do
    dose = timed_medication!(profile: @alice, starts_on: @day, times: %w[08:00 20:00])
    evening = dose.event.occurrence_for(@day + 1, time: "20:00")
    evening.complete!

    Occurrences::Destroy.call(evening, by: @alice, scope: "occurrence")

    assert_not Occurrence.exists?(evening.id)
    assert_equal [ "08:00" ], dose.event.reload.occurrences_between(@day + 1, @day + 1).map(&:time_string)
    assert_equal %w[08:00 20:00], dose.event.occurrences_between(@day + 2, @day + 2).map(&:time_string)
  end

  test "destroying one day of a series skips that date" do
    event = weekly_event(profile: @alice, type: "Appointment", starts_on: @day, title: "Checkup")
    second = event.occurrence_on(@day + 7).tap(&:materialize!)

    Occurrences::Destroy.call(second, by: @alice, scope: "occurrence")

    assert_not Occurrence.exists?(second.id)
    assert event.reload.excluded_on?(@day + 7)
    assert_equal 0, event.occurrences.count
    assert_equal [ @day ], event.occurrences_between(@day, @day + 7).map(&:date)
  end

  test "destroying one dose cancels what was asked about that dose, and only that" do
    link!(@alice, @bob)
    series = series!("Medication", profile: @alice, starts_on: @day, title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    morning = series.occurrence_on(@day + 1, time: "08:00")
    evening = series.occurrence_on(@day + 1, time: "20:00")
    about_morning = Links::Approvals::Hold.call(requester: @bob, record: morning, kind: :complete)
    about_evening = Links::Approvals::Hold.call(requester: @bob, record: evening, kind: :complete)
    whole_series = Links::Approvals::Hold.call(requester: @bob, record: evening, kind: :destroy, scope: "series")

    Occurrences::Destroy.call(evening, by: @alice)

    assert_predicate about_evening.reload, :cancelled?
    assert_predicate about_morning.reload, :pending?
    assert_predicate whole_series.reload, :pending?, "deleting the whole series can still be done"

    Links::Approvals::Decide.call(whole_series, approve: true)
    assert_predicate whole_series.reload, :approved?
    assert_not Event.exists?(series.id)
  end

  test "destroying a saved day cancels what was asked about it, and a day removed whole every dose of it" do
    link!(@alice, @bob)
    task = weekly_event(profile: @alice, type: "Task", starts_on: @day, title: "Plants")
    saved = task.occurrence_on(@day + 7).tap(&:materialize!)
    about_saved = Links::Approvals::Hold.call(requester: @bob, record: saved, kind: :complete)
    series = series!("Medication", profile: @alice, starts_on: @day, title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    about_dose = Links::Approvals::Hold.call(requester: @bob, record: series.occurrence_on(@day + 1, time: "08:00"), kind: :complete)

    Occurrences::Destroy.call(saved, by: @alice)
    Occurrences::Destroy.call(series.occurrence_on(@day + 1), by: @alice)

    assert_predicate about_saved.reload, :cancelled?
    assert_predicate about_dose.reload, :cancelled?
  end

  test "destroying a projected day of a series only skips it" do
    event = weekly_event(profile: @alice, type: "Task", starts_on: @day, title: "Plants")
    projected = event.occurrence_on(@day + 7)

    Occurrences::Destroy.call(projected, by: @alice)

    assert event.reload.excluded_on?(@day + 7)
    assert Event.exists?(event.id)
  end

  test "destroying a one-off removes the series, keeping its cost as a plain expense" do
    visit = appointment!(profile: @alice, date: @day)
    cost = expense!(profile: @alice, date: @day, cents: 5000, about: visit)

    Occurrences::Destroy.call(visit, by: @alice)

    assert_not Event.exists?(visit.event_id)
    cost.reload
    assert_nil cost.own_details.about
    assert_nil cost.event.details.reload.about
    assert_predicate cost.event, :valid?
  end

  test "destroying a series gives its drawn-down supplies back and cancels what was asked about it" do
    purchase = supply_purchase!(profile: @alice, name: "Cobalamin vial", quantity: 5)
    dose = medication!(profile: @alice, date: @day)
    dose.event.details.supply_uses.create!(supply: purchase.supply, quantity: 1)
    dose.complete!
    assert_equal 4, purchase.reload.quantity_remaining
    link!(@alice, @bob)
    approval = Links::Approvals::Hold.call(requester: @bob, record: dose, kind: :uncomplete)

    Occurrences::Destroy.call(dose, by: @alice, scope: "series")

    assert_equal 5, purchase.reload.quantity_remaining
    assert_not Event.exists?(dose.event_id)
    assert_predicate approval.reload, :cancelled?
  end

  test "destroying a repeating series takes every saved day and its values, in the queries one day takes" do
    queries = [ 1, 3 ].map do |weeks|
      event = series!("LabTestResult", profile: @alice, starts_on: @day, title: "Panel", rrule: "FREQ=WEEKLY")
      days = Array.new(weeks) { |week| day!(event, date: @day + (7 * week)) }
      days.each { |day| day.lab_test_result_entries.create!(analyte: Analyte.find_or_create_by_name("Calcium", profile_id: @alice.id), value: "9") }

      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          Occurrences::Destroy.call(days.first, by: @alice, scope: "series")
        end
      end

      assert_not Event.exists?(event.id)
      assert_not Occurrence.exists?(id: days.map(&:id))
      assert_not LabTestResultEntry.exists?(occurrence_id: days.map(&:id))
      count
    end

    assert_equal queries.first, queries.last
  end

  test "many days at once: a repeating series' days excluded, a one-off gone, the calendars that saw them refreshed" do
    weekly = weekly_event(profile: @alice, type: Task, starts_on: @day, title: "Bins")
    first = day!(weekly, date: @day)
    second = day!(weekly, date: @day + 7)
    once = task!(profile: @alice, date: @day + 1)
    link!(@alice, @bob)
    refreshed = []

    swapping(Calendar::Refresh, :call, ->(*profiles) { refreshed.concat(profiles) }) do
      assert_equal :occurrence, Occurrences::Destroy.call([ first, second, once ], by: @alice)
    end

    assert weekly.reload.excluded_on?(@day)
    assert weekly.excluded_on?(@day + 7)
    assert_not Occurrence.exists?(id: [ first.id, second.id ])
    assert Event.exists?(weekly.id), "the series goes on"
    assert_not Event.exists?(once.event_id), "a one-off goes with its day"
    assert_equal [ @alice, @bob ].sort_by(&:id), refreshed.uniq.sort_by(&:id), "its owner, and who reads tasks through the link"
  end

  test "a deleted day leaves the calendars that showed it, a housemate's too, though the series went with it" do
    visit = appointment!(profile: @alice, date: Date.new(2026, 10, 14), title: "Dentist")
    visit.event.event_shares.create!(profile: @bob)
    room = "profile_#{@bob.id}:2026-10"
    CalendarWatch.watch!(room, "bob's tab")

    pushed = capture_broadcasts(room) { Occurrences::Destroy.call(visit, by: @alice) }

    assert_equal 1, pushed.size
    assert_includes pushed.first, %(target="day_2026-10-14")
    assert_not_includes pushed.first, "Dentist"
  end

  test "only the owner may destroy" do
    visit = appointment!(profile: @alice, date: @day)

    assert_raises(Pundit::NotAuthorizedError) do
      Occurrences::Destroy.call(visit, by: @carol)
    end
    assert Occurrence.exists?(visit.id)
  end

  # --- Transactions::SetCost ---------------------------------------------

  test "a cost attached to a day is an expense about that day, updated in place" do
    visit = appointment!(profile: @alice, date: @day)

    result = Transactions::SetCost.call(visit, date: @day, title: "Visit", amount: "50", payment_method: "card", counterpart: "Moretti")
    cost = result.cost
    assert_predicate cost, :pending?
    assert_equal 5000, cost.details.amount_cents
    assert_equal "healthcare", cost.details.category
    assert_equal "Moretti", cost.details.counterparty
    assert_equal visit.event, cost.event.details.about, "the series' row names the visit's series"
    assert_equal visit, cost.own_details.about, "the day's row names the day"
    assert_equal [ cost ], visit.reload.costs.to_a

    again = Transactions::SetCost.call(visit, date: @day + 1, title: "Visit", amount: "60", payment_method: "cash", status: :completed)
    assert_equal cost, again.cost
    assert_equal @day, again.moved_from
    assert_equal 6000, cost.reload.details.amount_cents
    assert_equal @day + 1, cost.date
    assert_equal @day + 1, cost.event.reload.starts_on
    assert_predicate cost, :pending?, "the status is set when the cost is made, not on every save"
  end

  test "a cost attached to a purchase is about the purchase" do
    purchase = supply_purchase!(profile: @alice, name: "Needles")

    cost = Transactions::SetCost.call(purchase, date: @day, title: purchase.cost_title, amount: "12", payment_method: "card", status: :completed).cost

    assert_predicate cost, :completed?
    assert_equal purchase, cost.event.details.about
    assert_nil cost.own_details
    assert_equal [ cost ], purchase.costs.to_a
    assert_equal cost, purchase.cost
  end

  test "a projected day of a recurring series gets its row when a cost is attached to it" do
    event = weekly_event(profile: @alice, type: "Appointment", starts_on: @day, title: "Physio")
    next_week = event.occurrence_on(@day + 7)

    cost = Transactions::SetCost.call(next_week, date: @day + 7, title: "Physio", amount: "30", payment_method: "card").cost

    assert_predicate next_week, :persisted?
    assert_equal next_week, cost.own_details.about
    assert_equal [ cost ], event.occurrence_on(@day + 7).costs.to_a
    assert_empty event.occurrence_on(@day).costs
  end
end
