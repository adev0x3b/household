# frozen_string_literal: true

require "test_helper"

class OccurrenceTest < ActiveSupport::TestCase
  test "a universal field is the day's own when set, else the series'" do
    day = occurrences(:groceries_due)
    assert_equal "Buy groceries", day.title
    assert_nil day.own_title

    day.update!(title: "Buy groceries and bread")
    assert_equal "Buy groceries and bread", day.title
    assert_equal "Buy groceries", day.event.title
    assert_equal "Buy groceries", occurrences(:groceries_done).title, "the other days still read the series"

    day.event.update!(title: "Shop")
    assert_equal "Shop", occurrences(:groceries_done).reload.title, "editing the series edits every day not overridden"
    assert_equal "Buy groceries and bread", day.reload.title
  end

  test "assigning a day's own values keeps only what differs from the series, on the day and on its kind's row" do
    day = occurrences(:groceries_due)

    day.assign_own(title: "Buy groceries", notes: "And bread")
    assert_nil day.own_title, "a value equal to the series' is not the day's own"
    assert_equal "And bread", day.own_notes

    day.assign_own(notes: nil)
    assert_nil day.own_notes, "set back to the series' value, the day follows it again"

    row = occurrences(:methotrexate_taken).own_details
    row.assign_own(side: "left", quantity: "0.5")
    assert_nil row.own_side, "the series' side"
    assert_nil row.own_quantity, "the series' quantity, as the column holds it"
    row.assign_own(side: "right")
    assert_equal "right", row.own_side
  end

  test "the kind's fields come from the day's override row, else the series' row" do
    first, second = occurrences(:methotrexate_due), occurrences(:methotrexate_taken)
    assert_nil first.own_details
    assert_equal "left", first.details.side
    assert_equal "right", second.details.side
    assert_equal "left", second.own_details.series_row.side
    assert_equal BigDecimal("0.5"), second.details.quantity, "an override inherits what it doesn't set"
    assert_nil second.own_details.own_quantity
  end

  test "a meal day with its own row but no recipes of its own cooks the series' recipes" do
    recipe = Recipe.create!(profile: profiles(:alice), name: "Risotto")
    day = meal_on(profiles(:alice), Date.new(2026, 3, 2), recipes: [ recipe ])

    day.write_details!(kind: :ordered_in)

    assert_equal "ordered_in", day.details.kind
    assert_equal [ recipe ], day.details.resolved_recipes.to_a
  end

  test "writing a day's kind fields creates its override row, materializing the day" do
    day = events(:water_the_plants).occurrence_on(Date.new(2026, 3, 9))
    assert_predicate day, :projected?

    day.write_details!(priority: :urgent)

    assert_predicate day, :persisted?
    assert_equal "urgent", day.details.priority
    assert_equal "medium", day.event.details.priority
    assert_equal day, day.own_details.occurrence
    assert_equal 1, Task::Details.overrides.where(event_id: day.event_id).count
  end

  test "a day's own row of fields is its series' row: one naming another series' day is refused" do
    day = occurrences(:groceries_due)

    assert_predicate Task::Details.new(event: day.event, occurrence: day, priority: :high), :valid?
    stray = Task::Details.new(event: events(:water_the_plants), occurrence: day, priority: :high)
    assert_not stray.valid?
    assert stray.errors.of_kind?(:occurrence, :invalid)
  end

  test "a status the kind doesn't allow, a reason without skipped, an unknown reason" do
    appointment = events(:endocrinologist).occurrence_on(Date.new(2026, 3, 16))
    appointment.status = :in_progress
    assert_not appointment.valid?
    assert_predicate appointment.errors[:status], :any?

    task = events(:groceries).occurrence_on(Date.new(2026, 3, 16))
    task.status = :in_progress
    assert_predicate task, :valid?

    dose = events(:methotrexate).occurrence_on(Date.new(2026, 3, 16))
    dose.skipped_reason = "forgot"
    assert_not dose.valid?, "a reason without skipped"
    dose.status = :skipped
    assert_predicate dose, :valid?
    dose.skipped_reason = "lazy"
    assert_not dose.valid?, "not one of the kind's reasons"
    task.status = :skipped
    task.skipped_reason = "forgot"
    assert_not task.valid?, "a task knows no reasons"
  end

  test "a done day says when it was done, and no other day does" do
    day = events(:groceries).occurrence_on(Date.new(2026, 3, 16))
    day.status = :completed
    assert_not day.valid?
    assert day.errors.of_kind?(:completed_at, :blank)

    day.completed_at = Time.zone.local(2026, 3, 16, 9)
    assert_predicate day, :valid?

    day.status = :skipped
    assert_not day.valid?
    assert day.errors.of_kind?(:completed_at, :present)
  end

  test "complete! saves a projected day as done and change_status! walks the lifecycle" do
    day = events(:water_the_plants).occurrence_on(Date.new(2026, 3, 9))
    day.complete!(at: Time.zone.local(2026, 3, 9, 10))
    assert_predicate day, :persisted?
    assert_predicate day, :completed?
    assert_equal 0, day.days_offset

    day.uncomplete!
    assert_predicate day, :pending?
    assert_nil day.completed_at

    day.change_status!("skipped")
    assert_predicate day, :skipped?
    day.change_status!("completed")
    assert_predicate day, :completed?
    day.change_status!("in_progress")
    assert_predicate day, :in_progress?
    assert_nil day.completed_at
  end

  test "a status change reads the day under its lock: skipping a dose a housemate just took gives its stock back" do
    alice = profiles(:alice)
    purchase = supply_purchase!(profile: alice, name: "Vial", quantity: 5)
    dose = medication!(profile: alice, date: Date.current)
    dose.event.details.supply_uses.create!(supply: purchase.supply, quantity: 1)

    read_before = Occurrence.find(dose.id)
    Occurrence.find(dose.id).complete!
    assert_equal 4, purchase.reload.quantity_remaining

    read_before.change_status!("skipped")

    assert_predicate dose.reload, :skipped?
    assert_nil dose.completed_at
    assert_equal 5, purchase.reload.quantity_remaining, "a skipped dose drew nothing"
  end

  test "a day two people found unsaved is stored once: the second press acts on the row the first made" do
    alice = profiles(:alice)
    purchase = supply_purchase!(profile: alice, name: "Vial", quantity: 5)
    event = medication!(profile: alice, date: Date.current).event
    event.details.supply_uses.create!(supply: purchase.supply, quantity: 1)
    date = Date.current + 1
    first, second, third = Array.new(3) { Event.find(event.id).occurrence_on(date) }

    first.mark_completed!(true)
    second.mark_completed!(true)

    assert_equal 1, event.occurrences.where(date: date).count
    assert_equal first.id, second.id
    assert_equal 4, purchase.reload.quantity_remaining, "the dose was taken once"

    third.change_status!("skipped")

    assert_predicate first.reload, :skipped?
    assert_equal 5, purchase.reload.quantity_remaining
  end

  test "why a dose wasn't taken goes with skipped and is cleared by any other status" do
    dose = occurrences(:metformin_morning)

    dose.change_status!("skipped", reason: "forgot")
    assert_predicate dose.reload, :skipped?
    assert_equal "forgot", dose.skipped_reason

    dose.change_status!("pending")
    assert_nil dose.reload.skipped_reason

    dose.change_status!("skipped", reason: "not_available")
    dose.complete!
    assert_predicate dose.reload, :completed?
    assert_nil dose.skipped_reason
  end

  test "skipping or cancelling a day cancels its unpaid costs, reopening restores them" do
    visit = occurrences(:endocrinologist_due)
    fee = expense!(profile: profiles(:alice), date: visit.date, cents: 5000, status: :pending, about: visit)
    assert_equal [ fee ], visit.costs.to_a

    visit.change_status!("cancelled")
    assert_predicate fee.reload, :cancelled?

    visit.change_status!("pending")
    assert_predicate fee.reload, :pending?

    fee.complete!
    visit.change_status!("skipped")
    assert_predicate fee.reload, :completed?, "a paid cost is left alone"
  end

  test "how far from its date a day was done: days early, days late, none while it isn't" do
    day = events(:water_the_plants).occurrence_on(Date.new(2026, 3, 9))
    assert_nil day.days_offset

    day.complete!(at: Time.zone.local(2026, 3, 7, 10))
    assert_equal 2, day.days_offset
    day.update!(completed_at: Time.zone.local(2026, 3, 12, 10))
    assert_equal(-3, day.days_offset)
  end

  test "a day knows its key, its labels and whether it is still open" do
    dose = occurrences(:metformin_morning)
    assert_equal [ Date.new(2026, 3, 2), "08:00" ], dose.key
    assert_equal "with breakfast", dose.time_label
    assert_equal "with breakfast", dose.when_label
    dose.anchor = nil
    assert_equal "08:00", dose.time_label
    assert_equal "at 08:00", dose.when_label
    assert_nil occurrences(:methotrexate_due).time_label
    assert_equal [ Date.new(2026, 3, 2), nil ], occurrences(:methotrexate_due).key
    assert_predicate dose, :open?
    assert_not occurrences(:groceries_done).open?
    assert_equal "Metformin", dose.event_label
    assert_equal :healthcare, dose.section
  end

  test "two doses of a day at different times are two rows, at the same time one" do
    event = events(:metformin)
    day = occurrences(:metformin_morning).date

    evening = Occurrence.new(event: event, date: day, time: "19:30", anchor: "CV")
    assert_predicate evening, :valid?
    evening.save!

    again = Occurrence.new(event: event, date: day, time: "08:00")
    assert_not again.valid?
    assert_includes again.errors[:date], "has already been taken"

    untimed = Occurrence.new(event: event, date: day)
    assert_predicate untimed, :valid?, "an untimed day is its own slot"
    untimed.save!
    assert_not Occurrence.new(event: event, date: day).valid?
    assert_raises(ActiveRecord::RecordNotUnique) { Occurrence.new(event: event, date: day).save!(validate: false) }
  end

  test "children materialize the day" do
    day = events(:bloodwork).occurrence_on(Date.new(2026, 3, 16))
    day.lab_test_result_entries.build(analyte: analytes(:glucose), unit: units(:mgdl), value: "90")
    day.save!

    assert_predicate day, :persisted?
    assert_equal 1, day.lab_test_result_entries.count
  end

  test "deleting days takes everything that points at them: every table the schema says, and the costs about them" do
    alice = profiles(:alice)
    visit = occurrences(:endocrinologist_due)
    fee = expense!(profile: alice, date: visit.date, cents: 5000, about: visit)
    visit.write_details!(counterpart: "Dr. Bianchi")
    bloodwork = occurrences(:bloodwork_done)
    needles = supply_purchase!(profile: alice, name: "Needles", quantity: 10).supply
    dose = occurrences(:metformin_morning)
    dose.event.details.replace_uses!([ [ needles.id, "1" ] ])
    dose.complete!
    pantry_ingredient(alice, "Lentils", quantity: 1)
    meal = meal_on(alice, Date.new(2026, 3, 2), recipes: [ recipe_with(alice, "Soup", [ "Lentils", 200, "g" ]) ], status: :completed)
    Meal::Consumption.new(meal).record!
    link!(alice, profiles(:bob))
    request = Links::Approvals::Hold.call(requester: profiles(:bob), record: visit, kind: :complete)
    days = [ visit, bloodwork, dose, meal ]
    rows = {
      "appointment_details" => visit.own_details, "lab_test_result_entries" => bloodwork.lab_test_result_entries.first,
      "supply_consumptions" => dose.supply_consumptions.first, "meal_consumptions" => meal.meal_consumptions.first,
      "link_approvals" => request
    }
    tables = ActiveRecord::Base.connection.tables.select { |table| ActiveRecord::Base.connection.foreign_keys(table).any? { _1.to_table == "occurrences" } }
    tables.each { |table| assert rows[table] || Details::Base.descendants.any? { _1.table_name == table }, "#{table} points at a day: give the test a row in it" }
    rows.each_value { |row| assert_predicate row, :present? }

    Occurrence.delete_with_children(days)

    assert_empty Occurrence.where(id: days.map(&:id))
    rows.each do |table, row|
      next if table == "link_approvals"

      assert_not row.class.exists?(row.id), "a row of #{table} is left pointing at a deleted day"
    end
    assert_nil request.reload.occurrence_id, "a request about the day is kept, pointing at nothing"
    assert_nil fee.reload.details.about, "the cost lets go of the day"
  end

  test "a day resolves its policy through its kind" do
    assert_equal OccurrencePolicy, occurrences(:groceries_due).policy_class
    assert_equal TransactionOccurrencePolicy, occurrences(:electricity_due).policy_class
  end

  test "with_series resolves a kind's field in SQL as the day reads it" do
    sides = Occurrence.of_type(Medication).with_series(Medication).where(events: { id: events(:methotrexate).id })
      .order(:date).pluck(Arel.sql(Occurrence.resolved_sql(:side, type: Medication)))
    assert_equal [ 0, 1 ], sides
    titles = Occurrence.with_series(Task).where(events: { id: events(:groceries).id }).order(:date).pluck(Arel.sql(Occurrence.resolved_sql(:title)))
    assert_equal [ "Buy groceries", "Buy groceries" ], titles
  end

  test "resolved_sql takes only a column the day, its series or its kind's details have: nothing else reaches the SQL" do
    assert_equal "events.rrule", Occurrence.resolved_sql(:rrule)
    assert_raises(ArgumentError) { Occurrence.resolved_sql("1; DROP TABLE events") }
    assert_raises(ArgumentError) { Occurrence.resolved_sql(:nope, type: Medication) }
  end
end
