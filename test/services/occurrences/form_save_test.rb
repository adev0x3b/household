# frozen_string_literal: true

require "test_helper"

class Occurrences::FormSaveTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
  end

  def form(type, params, record: nil, actor: @alice, owner: nil)
    Occurrences::FormSave.for(type).new(actor: actor, owner: owner, params: params, record: record)
  end

  test "a new series is saved on the owner's calendar, with its recurrence and its kind's fields" do
    save = form("Task", { task: { title: "Water plants", date: "2026-11-02", details_attributes: { priority: "high" } },
                          event: { frequency: "weekly", interval: "1", week_days: [ "monday" ] } }, owner: @bob)

    assert_predicate save, :new_series?
    assert_equal :create?, save.policy_query
    assert save.save
    assert_equal @bob, save.event.profile
    assert_predicate save.event, :recurring?
    assert_equal "Water plants", save.event.reload.title
    assert_equal "high", save.event.details.priority
    assert_predicate save.record, :projected?, "the first day needs no row yet"
  end

  test "a projected day of a series is saved on that series as its own day" do
    event = events(:water_the_plants)
    save = form("Task", { task: { title: "Buy bread too", event_id: event.id, date: "2026-03-16", details_attributes: { priority: "urgent" } } })

    assert_predicate save, :materializing?
    assert_equal :edit?, save.policy_query
    assert save.save
    assert_equal event, save.record.event
    assert_predicate save.record, :persisted?
    assert_equal "Buy bread too", save.record.own_title
    assert_equal "urgent", save.record.own_details.priority
    assert_equal "Water the plants", event.reload.title, "the series is untouched"
  end

  test "a day's fields go to the whole series when the form says so" do
    event = events(:water_the_plants)
    save = form("Task", { task: { title: "Water everything", event_id: event.id, date: "2026-03-16", apply_to: "series" } })

    assert save.save
    assert_equal "Water everything", event.reload.title
    assert_nil save.record.own_title
  end

  test "a day stores only what differs from its series, so it keeps following the series" do
    event = events(:water_the_plants)
    save = form("Task", { task: { title: event.title, notes: "Only the basil", event_id: event.id, date: "2026-03-16",
                                  details_attributes: { priority: event.details.priority } } })

    assert save.save
    day = save.record.reload
    assert_nil day.own_title
    assert_equal "Only the basil", day.own_notes
    assert_nil day.own_details, "a priority equal to the series' needs no row"

    event.update!(title: "Water the garden")
    assert_equal "Water the garden", day.reload.title
  end

  test "setting a day's field back to the series' value lets it follow the series again" do
    event = events(:water_the_plants)
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap { |d| d.update!(title: "Just the ferns") }
    day.write_details!(priority: :urgent)

    assert form("Task", { task: { title: event.title, details_attributes: { priority: event.details.priority } } }, record: day).save
    assert_nil day.reload.own_title
    assert_nil day.own_details.own_priority
    assert_equal event.details.priority, day.details.priority
  end

  test "a new series waiting for its owner's OK keeps the day it starts on" do
    payload = form("Task", { task: { title: "Mow", date: "2026-11-02" }, event: { frequency: "none" } }, owner: @bob).payload

    assert_equal "2026-11-02", payload.dig("task", "date")
  end

  test "a failed save of a projected day shows that day of its series again" do
    event = weekly_event(profile: @alice, type: Appointment, starts_on: Date.new(2026, 3, 2))
    save = form("Appointment", { appointment: { title: "Check-up", event_id: event.id, date: "2026-03-16" }, transaction: { amount: "not money" } })

    assert_not save.save
    assert_equal event, save.record.event
    assert_predicate save.record, :new_record?
    assert_equal Date.new(2026, 3, 16), save.record.date
    assert_equal "Check-up", save.record.title
    assert_predicate save.record.errors, :any?
    assert_not event.occurrences.exists?, "the day's row went with the failed cost"
  end

  test "the whole series takes only what was changed on a day's form, and that day follows it" do
    event = events(:water_the_plants)
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap { |d| d.update!(notes: "Only the basil", title: "Just the ferns") }

    assert form("Task", { task: { title: "Water everything", notes: "Only the basil", apply_to: "series" } }, record: day).save
    event.reload
    assert_equal "Water everything", event.title
    assert_not_equal "Only the basil", event.notes, "the day's own notes stay the day's"
    assert_nil day.reload.own_title, "the day follows the series in what it changed"
    assert_equal "Water everything", day.title
    assert_equal "Only the basil", day.own_notes
  end

  test "editing a done day through the whole series shows what was typed there; the other done days keep theirs" do
    event = events(:water_the_plants)
    before = event.title
    done = day!(event, date: Date.new(2026, 3, 9), status: :completed)
    edited = day!(event, date: Date.new(2026, 3, 16), status: :completed)

    assert form("Task", { task: { title: "Water everything", apply_to: "series" } }, record: edited).save
    assert_equal "Water everything", edited.reload.title
    assert_equal before, done.reload.title
  end

  test "editing a one-off edits its series; the status goes through change_status!, and the recurrence stays when none was sent" do
    day = occurrences(:groceries_due)

    assert form("Task", { task: { title: "Renamed", status: "completed" } }, record: day).save
    day.reload
    assert_equal "Renamed", day.event.title
    assert_nil day.own_title
    assert_predicate day, :completed?
    assert_not_nil day.completed_at
    assert_nil day.event.rrule
  end

  test "a skipped dose keeps its reason, a taken one its time" do
    dose = occurrences(:metformin_morning)

    assert form("Medication", { medication: { status: "skipped", skipped_reason: "forgot" } }, record: dose).save
    assert_equal "forgot", dose.reload.skipped_reason

    assert form("Medication", { medication: { status: "completed", completed_at: "2026-03-02 08:15" } }, record: dose).save
    assert_predicate dose.reload, :completed?
    assert_equal @alice.zone.parse("2026-03-02 08:15"), dose.completed_at
  end

  test "an invalid series is not saved and keeps its errors" do
    save = form("Task", { task: { title: "", date: "2026-11-02" } })

    assert_no_difference "Event.count" do
      assert_not save.save
    end
    assert save.record.errors[:title].any? || save.event.errors[:title].any?
  end

  test "an appointment's cost becomes its attached payment, named after who it was with" do
    save = form("Appointment", { appointment: { title: "Dentist", date: "2026-11-03", details_attributes: { kind: "medical", counterpart: "Dr. Tooth" } },
                                 event: { frequency: "none" }, transaction: { amount: "80", payment_method: "card" } })

    assert_difference "Transaction.count", 1 do
      assert save.save
    end
    cost = save.record.reload.costs.sole
    assert_equal 80, cost.details.amount
    assert_equal "healthcare", cost.details.category
    assert_equal "Dr. Tooth", cost.details.counterparty
    assert_match "Dr. Tooth", cost.event.title
  end

  test "a social appointment's cost is filed under entertainment" do
    save = form("Appointment", { appointment: { title: "Dinner", date: "2026-11-03", details_attributes: { kind: "social", counterpart: "Sam" } },
                                 event: { frequency: "none" }, transaction: { amount: "40", payment_method: "cash" } })
    assert save.save
    assert_equal "entertainment", save.record.costs.sole.details.category
    assert_equal :agenda, save.event.section
  end

  test "a cost that can't be saved rolls the new appointment back and shows its errors" do
    save = form("Appointment", { appointment: { title: "Dentist", date: "2026-11-03", details_attributes: { counterpart: "Dr. Tooth" } },
                                 event: { frequency: "none" }, transaction: { amount: "not money" } })

    assert_no_difference [ "Appointment.count", "Event.count", "Transaction.count" ] do
      assert_not save.save
    end
    assert_predicate save.record, :new_record?
    assert_predicate save.record.errors, :any?
  end

  test "a payload holds only what an update changes" do
    day = occurrences(:groceries_due)
    save = form("Task", { task: { title: "Renamed", notes: day.notes, status: day.status, details_attributes: { priority: day.details.priority } },
                          event: { frequency: "none" } }, record: day)

    assert_predicate save, :valid_for_hold?
    assert_equal({ "task" => { "title" => "Renamed" } }, save.payload)
    assert_equal [ { "attribute" => "title", "from" => "Buy groceries", "to" => "Renamed" } ], save.preview
    assert_equal "Buy groceries", day.reload.title
  end

  test "a payload of a projected day keeps the series and the day it belongs to" do
    event = events(:water_the_plants)
    save = form("Task", { task: { title: "Shop", event_id: event.id, date: "2026-03-16" }, event: { frequency: "none" } })

    payload = save.payload
    assert_equal event.id.to_s, payload.dig("task", "event_id")
    assert_equal "2026-03-16", payload.dig("task", "date")
    assert_equal "none", payload.dig("event", "frequency")
  end

  test "a lab report's values go to the day" do
    day = occurrences(:bloodwork_due)
    save = form("LabTestResult", { lab_test_result: { lab_test_result_entries_attributes: [ { analyte_name: "TSH", value: "2.1", unit_name: "mIU/L" } ] } }, record: day)

    assert save.save
    assert_equal 1, day.reload.lab_test_result_entries.count
  end

  test "a medication's planned uses go to its details, and a taken dose re-draws them" do
    needles = supply_purchase!(profile: @alice, name: "Needles", quantity: 10)
    dose = occurrences(:methotrexate_taken)
    assert_predicate dose, :completed?

    assert form("Medication", { medication: { status: "completed", details_attributes: { supply_uses_attributes: [ { supply_id: needles.supply_id, quantity: "2" } ] } } }, record: dose).save

    assert_equal [ [ needles.supply_id, "2.0" ] ], dose.reload.event.details.uses_list, "a one-off's uses are the series'"
    assert_equal 8, needles.reload.quantity_remaining
  end

  test "only a kind of series has a form" do
    assert_raises(ArgumentError) { Occurrences::FormSave.for("Spaceship") }
  end

  test "a projected day given only its kind's own field gets a row, the field as its own" do
    event = events(:water_the_plants)
    save = form("Task", { task: { event_id: event.id, date: "2026-03-16", details_attributes: { priority: "urgent" } } })

    assert save.save
    assert_predicate save.record, :persisted?
    assert_equal "urgent", save.record.own_details.priority
  end

  test "a day that can't be saved says why and saves nothing" do
    event = events(:water_the_plants)
    save = form("Task", { task: { event_id: event.id, date: "2026-03-16", duration_minutes: "-5" } })

    assert_not save.save
    assert_predicate save.record.errors, :any?
    assert_not event.occurrences.exists?(date: Date.new(2026, 3, 16))
  end

  test "a form held for its owner carries a dose's time, the scope and a fee, and shows the owner each change" do
    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    dose = form("Medication", { medication: { event_id: twice.id, date: "2026-10-07", time: "20:00", apply_to: "series",
                                              details_attributes: { quantity: "2", supply_uses_attributes: [ { supply_id: "1", quantity: "1" } ] } } }, actor: @bob)
    payload = dose.payload["medication"]
    assert_equal [ twice.id.to_s, "2026-10-07", "20:00", "series" ], payload.values_at("event_id", "date", "time", "apply_to")
    assert_equal [ [ "quantity", "2" ] ], dose.preview.map { _1.values_at("attribute", "to") }, "a list isn't a row"

    visit = form("Appointment", { appointment: { title: "Dentist", date: "2026-10-09", details_attributes: { kind: "medical" } },
                                  transaction: { amount: "50", payment_method: "card" } }, actor: @bob, owner: @alice)
    assert_equal({ "amount" => "50", "payment_method" => "card" }, visit.payload["transaction"])
    assert_includes visit.preview, { "attribute" => "amount", "from" => nil, "to" => "50" }
    assert_predicate visit, :valid_for_hold?
  end

  test "a held payment keeps its own fields: its key is not read as a cost section" do
    payment = form("Transaction", { transaction: { title: "Rent", date: "2026-10-09", details_attributes: { amount: "700", kind: "expense" } } }, actor: @bob, owner: @alice)

    assert_equal({ "amount" => "700", "kind" => "expense" }, payment.payload.dig("transaction", "details_attributes"))
    assert_equal "Rent", payment.payload.dig("transaction", "title")
    assert_not_includes payment.preview.map { _1["attribute"] }, "payment_method"
  end

  test "a held change to a saved day carries its new status, when it was done, and its time as the clock reads it" do
    event = events(:water_the_plants)
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    held = form("Task", { task: { title: event.title, status: "completed", completed_at: "2026-03-16T18:00", start_time: "07:30" } }, record: day, actor: @bob)
    assert_equal({ "status" => "completed", "completed_at" => "2026-03-16T18:00", "start_time" => "07:30" }, held.payload["task"].slice("status", "completed_at", "start_time"))
  end

  test "a day with its own value, edited for the whole series, takes the series' and keeps following it" do
    event = events(:water_the_plants)
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    day.write_details!(priority: :urgent)

    assert form("Task", { task: { title: event.title, apply_to: "series", details_attributes: { priority: "low" } } }, record: day).save
    assert_equal "low", event.details.reload.priority
    assert_nil day.reload.own_details.own_priority, "the day's own value gives way"
    assert_equal "low", day.details.priority
  end

  test "a day's own start time, shown on its form, stays the day's when the whole series is edited from there" do
    event = events(:water_the_plants).tap { |e| e.update!(start_time: "11:00") }
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap { |d| d.update!(start_time: "14:00") }

    assert form("Task", { task: { title: event.title, location: "The balcony", start_time: "14:00", apply_to: "series" } }, record: day).save
    event.reload
    assert_equal "The balcony", event.location
    assert_equal "11:00", event.start_time.strftime("%H:%M"), "the series keeps its own start time"
    assert_equal "11:00", event.occurrence_on(Date.new(2026, 3, 23)).start_time.strftime("%H:%M"), "the days to come keep it too"
    assert_equal "14:00", day.reload.own_start_time.strftime("%H:%M"), "the edited day keeps its own"
  end

  test "a payment's own amount, shown on its form as typed, stays the day's when the whole series is edited from there" do
    event = events(:electricity_bill).tap { |e| e.update!(rrule: "FREQ=WEEKLY;BYDAY=MO") }
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap { |d| d.write_details!(amount: "140") }
    details = { amount: "140.00", kind: event.details.kind, category: event.details.category,
                counterparty: event.details.counterparty, payment_method: event.details.payment_method }

    assert form("Transaction", { transaction: { title: event.title, notes: "Paid by card now", apply_to: "series", details_attributes: details } }, record: day).save
    assert_equal "Paid by card now", event.reload.notes
    assert_equal BigDecimal("125"), event.details.reload.amount, "the series keeps its own amount"
    assert_equal BigDecimal("140"), day.reload.details.amount, "the edited day keeps its own"
  end

  # A dose at 08:00 every day for two weeks, every one taken, its form open on today's.
  def metformin_taken_until_yesterday
    event = series!("Medication", profile: @alice, starts_on: Date.current - 14, title: "Metformin", slots: %w[08:00], rrule: "FREQ=DAILY")
    event.occurrences_between(event.starts_on, Date.current - 1).each(&:complete!)
    event
  end

  def unfinished_days_of(event)
    Reports::Unfinished.new(Reports::Audience.new(viewer: @alice), today: Date.current).entries(of: Medication) { _1.id == event.id }
  end

  test "a series with a past goes on from today under the rule and the times its form sends, its past kept" do
    travel_to Time.zone.local(2026, 10, 7, 12)
    event = metformin_taken_until_yesterday
    save = form("Medication", { medication: { event_id: event.id, date: Date.current.iso8601, time: "08:00", apply_to: "series" },
                                event: { frequency: "weekly", week_days: %w[wednesday], slots: [ "09:00" ], slots_submitted: "1" } })

    assert_difference "Event.count", 1 do
      assert save.save
    end
    assert_empty unfinished_days_of(event), "no 09:00 dose is owed for the mornings taken at 08:00"
    assert_equal Date.current - 1, Events::RecurrenceRule.describe(event.reload.rrule)[:ends]
    from_today = Medication.find_by!(profile: @alice, title: "Metformin", starts_on: Date.current)
    assert_equal [ "FREQ=WEEKLY;BYDAY=WE", [ [ "09:00", nil ] ] ], [ from_today.rrule, from_today.slots ]
  end

  test "the rule and the times a form sends again with every save change nothing" do
    travel_to Time.zone.local(2026, 10, 7, 12)
    event = metformin_taken_until_yesterday
    save = form("Medication", { medication: { event_id: event.id, date: Date.current.iso8601, time: "08:00", notes: "with water" },
                                event: { frequency: "daily", slots: [ "08:00" ], slots_submitted: "1" } })

    assert_no_difference "Event.count" do
      assert save.save
    end
    assert_equal [ "FREQ=DAILY", "with water" ], [ event.reload.rrule, save.record.reload.own_notes ]
  end

  test "a dose taken on the form that also changes the times is on the record first: the new times start tomorrow" do
    travel_to Time.zone.local(2026, 10, 7, 12)
    event = metformin_taken_until_yesterday
    save = form("Medication", { medication: { event_id: event.id, date: Date.current.iso8601, time: "08:00", apply_to: "series", status: "completed" },
                                event: { frequency: "daily", slots: [ "09:00" ], slots_submitted: "1" } })

    assert save.save
    assert_predicate save.record.reload, :completed?
    assert_equal Date.current, Events::RecurrenceRule.describe(event.reload.rrule)[:ends]
    assert_equal [ [ "09:00", nil ] ], Medication.find_by!(profile: @alice, title: "Metformin", starts_on: Date.current + 1).slots
  end

  test "a rule with no day to come is the form's error, and nothing changes" do
    travel_to Time.zone.local(2026, 10, 7, 12)
    event = metformin_taken_until_yesterday
    save = form("Medication", { medication: { event_id: event.id, date: Date.current.iso8601, time: "08:00", apply_to: "series" },
                                event: { frequency: "weekly", week_days: %w[tuesday], ends: Date.current.iso8601 } })

    assert_no_difference "Event.count" do
      assert_not save.save
    end
    assert_equal [ "has no day to come" ], save.record.errors[:rrule]
    assert_equal "FREQ=DAILY", event.reload.rrule
  end

  test "a held change to a dose's times alone carries them" do
    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    dose = twice.occurrences.sole
    held = form("Medication", { medication: { details_attributes: { quantity: "" } },
                                event: { frequency: "daily", slots: %w[09:00 21:00], slots_submitted: "1" } }, record: dose, actor: @bob)

    assert_equal %w[09:00 21:00], held.payload.dig("event", "slots")
    assert_equal [ { "attribute" => "recurrence", "from" => nil, "to" => "daily" } ], held.preview
  end

  test "a held change carries only what changed, however the form writes what it left alone" do
    event = events(:water_the_plants).tap { |e| e.update!(start_time: "11:00", duration_minutes: 30) }
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    held = form("Task", { task: { title: event.title, location: "The balcony", start_time: "11:00", duration_minutes: "30" } }, record: day, actor: @bob)

    assert_predicate held, :valid_for_hold?
    assert_equal({ "location" => "The balcony" }, held.payload["task"])
    assert_equal [ { "attribute" => "location", "from" => nil, "to" => "The balcony" } ], held.preview
  end

  test "a housemate filing the owner's series puts it only in a collection the owner reaches too" do
    event = events(:water_the_plants)
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    file_in = lambda do |collection|
      shape = { frequency: "weekly", interval: "1", week_days: [ "monday" ], collection_id: collection.id }
      form("Task", { task: { title: event.title }, event: shape }, record: day, actor: @bob).save
    end

    assert file_in.call(collections(:fibromyalgia))
    assert_nil event.reload.collection_id, "Bob's own collection is out of Alice's reach"

    assert file_in.call(collections(:b12))
    assert_equal collections(:b12), event.reload.collection, "Alice shared hers with Bob"
  end

  test "a held change that sends the series' rule as it is, and no collection, asks nothing of the series" do
    event = events(:water_the_plants).tap { |e| e.update!(collection: collections(:b12)) }
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    rule = { frequency: "weekly", interval: "1", week_days: [ "monday" ] }

    held = form("Task", { task: { title: "Water the basil" }, event: rule }, record: day, actor: @bob)
    assert_not held.payload.key?("event")
    assert_equal([ "title" ], held.preview.map { _1["attribute"] })

    moved = form("Task", { task: { title: event.title }, event: rule.merge(collection_id: "") }, record: day, actor: @bob)
    assert_equal "", moved.payload.dig("event", "collection_id"), "taking it out of its collection is a change"
  end

  test "a course of fifteen days twice a day ends on its fifteenth day, both doses of it included" do
    save = form("Medication", { medication: { title: "Amoxicillin", date: "2026-11-01", details_attributes: { kind: "pill" } },
                                event: { frequency: "daily", slots: %w[08:00 20:00], slots_submitted: "1",
                                         ends_by: "after_days", ends_after_days: "15" } })

    assert save.save
    event = save.event.reload
    assert_equal Date.new(2026, 11, 15), Events::RecurrenceRule.describe(event.rrule)[:ends]
    assert_equal 30, event.occurrences_between(Date.new(2026, 10, 1), Date.new(2026, 12, 31)).size
  end

  test "a number of times counts the days the series falls on" do
    save = form("Task", { task: { title: "Physio", date: "2026-11-02" },
                          event: { frequency: "weekly", week_days: %w[monday thursday], ends_by: "after_times", ends_after_times: "4" } })

    assert save.save
    assert_equal [ Date.new(2026, 11, 2), Date.new(2026, 11, 5), Date.new(2026, 11, 9), Date.new(2026, 11, 12) ],
                 save.event.reload.occurrences_between(Date.new(2026, 11, 1), Date.new(2026, 12, 31)).map(&:date)
  end

  test "an end before the first day, or a count of none, is the form's error under the end, and nothing is saved" do
    early = form("Task", { task: { title: "Physio", date: "2026-11-02" },
                           event: { frequency: "daily", ends_by: "on_date", ends: "2026-11-01" } })
    none = form("Task", { task: { title: "Physio", date: "2026-11-02" },
                          event: { frequency: "daily", ends_by: "after_days", ends_after_days: "0" } })

    assert_no_difference "Event.count" do
      assert_not early.save
      assert_not none.save
    end
    assert_equal [ "Repeats can't end before its first day" ], Forms::Errors.new(early.record).sentences
    assert_equal [ "Repeats must end after a whole number of days or times, from 1 to 999" ], Forms::Errors.new(none.record).for(:rrule)
  end

  test "a one-off has no end, whatever the end's fields say" do
    save = form("Task", { task: { title: "Mow", date: "2026-11-02" }, event: { frequency: "none", ends_by: "after_days", ends_after_days: "" } })

    assert save.save
    assert_nil save.event.reload.rrule
  end

  test "an end given to a series that exists counts from its first day, and keeps its days so far" do
    travel_to Time.zone.local(2026, 3, 20, 12)
    event = events(:water_the_plants) # Mondays from 2026-03-02
    day = event.occurrence_on(Date.new(2026, 3, 23))

    assert form("Task", { task: { title: event.title, apply_to: "series" },
                          event: { frequency: "weekly", interval: "1", week_days: [ "monday" ], ends_by: "after_times", ends_after_times: "5" } },
                record: day).save

    assert_equal Date.new(2026, 3, 30), Events::RecurrenceRule.describe(event.reload.rrule)[:ends]
    assert_equal 5, event.occurrences_between(Date.new(2026, 3, 1), Date.new(2026, 6, 30)).size
  end

  test "a housemate asking to end the owner's series with an end that can't be is told so when asking" do
    event = events(:water_the_plants)
    day = event.occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    held = form("Task", { task: { title: event.title },
                          event: { frequency: "weekly", interval: "1", week_days: [ "monday" ], ends_by: "on_date", ends: "2026-01-01" } },
                record: day, actor: @bob)

    assert_not held.valid_for_hold?
    assert_equal [ "Repeats can't end before its first day" ], Forms::Errors.new(held.record).sentences
  end
end
