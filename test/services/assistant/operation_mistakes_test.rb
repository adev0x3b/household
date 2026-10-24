# frozen_string_literal: true

require "test_helper"

# A call the model got wrong comes back in words that say how to fix it,
# and saves nothing.
class Assistant::OperationMistakesTest < ActiveSupport::TestCase
  NEEDLE = [ { supply: "Needles", quantity: 1 } ].freeze

  setup do
    @alice = profiles(:alice)
    @chat = assistant_chat(@alice)
    @task = occurrences(:groceries_due)
  end

  # What the model reads back about a call: its error, or what its changes
  # lack, got wrong, or left out.
  def told(*operations)
    result = submit_changes(@chat, operations)
    @chat = assistant_chat(@alice)
    changes = Array(result.dig(:data, :changes))
    lines = changes.flat_map { |change| Array(change[:problems]) + Array(change[:missing]) + Array(change[:notes]) }
    [ result[:error], *Array(result.dig(:data, :notes)), *lines ].compact.join(" | ")
  end

  # The same, for one operation with the fields it gives.
  def told_about(op, type: nil, ref: nil, **fields) = told({ op: op, type: type, ref: ref, fields: fields }.compact)

  def update_task(**fields) = told_about("update", type: "task", ref: @task.id, **fields)

  test "an update asks for fields its kind has, and something to change" do
    assert_match "values can only be changed on a lab_test_result", update_task(values: { "Calcium" => "3" })
    assert_match "can only be used on a grocery_list", update_task(check_items: [ "Flour" ])
    assert_match "can only be used on a meal", update_task(recipes: [ "Pancakes" ])
    assert_match "nothing to change", update_task
    assert_match "can't read the time", told_about("update", type: "medication", ref: occurrences(:methotrexate_due).id, anchor: "teatime soon")
    assert_match "can't read the time", told_about("update", type: "medication", ref: occurrences(:methotrexate_due).id, time: "whenever")
  end

  test "an update names fields the record has, the supplies only a medication's, and a price only a meal out's" do
    dose = occurrences(:methotrexate_due)
    visit = occurrences(:endocrinologist_due)
    assert_match "uses (the supplies each dose uses from now on)", told_about("update", type: "medication", ref: dose.id, colour: "red")
    assert_match "amount (its fee)", told_about("update", type: "appointment", ref: visit.id, colour: "red")
    recipe = told_about("update", type: "recipe", ref: recipes(:roast_chicken).id, colour: "red")
    assert_match "unknown fields colour", recipe
    assert_no_match "its fee", recipe, "a recipe has no price"
    assert_match "uses is only for a medication", update_task(uses: NEEDLE)
    assert_match "change the supplies and the repeat in two separate calls",
                 told_about("update", type: "medication", ref: dose.id, uses: NEEDLE, recurrence: { frequency: "weekly" })
    supper = meal_on(@alice, Date.new(2026, 10, 7), recipes: [ recipes(:roast_chicken) ])
    assert_match "a home meal has no price of its own", told_about("update", type: "meal", ref: supper.id, amount: "20", payment_method: "cash")
  end

  test "a status change says what it can't do" do
    dose = occurrences(:methotrexate_due)
    assert_match "uses is only for a medication dose", told_about("complete", type: "task", ref: @task.id, uses: NEEDLE)
    assert_match "skipped_reason goes with status skipped", told_about("complete", type: "task", ref: @task.id, skipped_reason: "forgot")
    assert_match "nothing still pending matched", told_about("complete", type: "task", all: true, query: "no such thing at all")
    assert_match "recipe can't be marked done", told_about("complete", type: "recipe", ref: recipes(:roast_chicken).id)
    assert_match "uses is for a dose being marked done", told_about("uncomplete", type: "medication", ref: dose.id, uses: NEEDLE)
    assert_match "skipped_reason must be one of",
                 told_about("set_status", type: "medication", ref: dose.id, status: "skipped", skipped_reason: "bored")
  end

  test "marking done what is done is a note; reopening a visit reopens the fee it paid" do
    AssistantEval::Seeds.moretti_oct2_with_fee(@alice)
    visit = appointments_with("Moretti").sole
    told_about("complete", type: "appointment", ref: visit.id)
    assert visit.reload.completed? && visit.costs.sole.completed?

    assert_match "is already completed", told_about("complete", type: "appointment", ref: visit.id)
    told_about("uncomplete", type: "appointment", ref: visit.id)
    assert_predicate visit.reload, :pending?
    assert_predicate visit.costs.sole, :pending?, "the fee it paid is reopened with it"
  end

  test "a deletion says what it couldn't find or may not touch" do
    assert_match "say which one", told_about("delete", type: "task", query: "no such thing at all")
    assert_match "nothing matched", told_about("delete", type: "task", ids: [ 0 ])
    bobs = Task.create!(profile: profiles(:bob), starts_on: Date.current, title: "Bob's chore")
      .occurrence_on(Date.current).materialize!
    assert_match "no task with id #{bobs.id}", told_about("delete", type: "task", ref: bobs.id), "someone else's reads as not there"

    Shares::Create.call(bobs.event, with: @alice, by: profiles(:bob))
    assert_match "isn't allowed to delete it", told_about("delete", type: "task", ref: bobs.id), "shared with her: seen, not deleted"
  end

  test "a new record names a kind that exists, and what it lacks or doesn't know is said" do
    assert_match "spaceship can't be created; types:", told_about("create", type: "spaceship")
    assert_match "not understood, not saved: task.flavour",
                 told_about("create", type: "task", title: "Repot the basil", date: "tomorrow", flavour: "mint")
    assert_match "not understood, not saved: transaction.amount",
                 told_about("create", type: "task", title: "Sharpen the knives", date: "tomorrow", price: "5"),
                 "a price for a kind that takes none"
    assert_match "supply_purchase.supply_name", told_about("create", type: "supply_purchase", quantity: 1)
    assert_match "'barter' is not a valid payment_method",
                 told_about("create", type: "transaction", title: "Plumber", date: "today", amount: "80", payment_method: "barter")
    assert_match "amount must be more than zero",
                 told_about("create", type: "transaction", title: "Plumber", date: "today", amount: "0", payment_method: "cash")
    assert_match "amount must be more than zero",
                 told_about("create", type: "transaction", title: "Plumber", date: "today", amount: "-80", payment_method: "cash"),
                 "the kind says which way the money went, not a sign"
    bought = told_about("create", type: "supply_purchase", supply: "Needles", quantity: 1, amount: "free", payment_method: "barter")
    assert_match "must be a number above zero", bought
    assert_match "must be one of", bought
  end

  test "sharing names a thing that can be shared, with someone it isn't shared with yet" do
    bob = profiles(:bob).first_name
    assert_match "can't be shared", told_about("share", type: "ingredient", ref: ingredients(:flour).id, with: bob)
    assert_match "already shared with #{bob}", told_about("share", type: "recipe", ref: recipes(:roast_chicken).id, with: bob)
    pesto = Recipe.create!(profile: @alice, name: "Pesto")
    assert_match "it isn't shared with #{bob}", told_about("unshare", type: "recipe", ref: pesto.id, with: bob)
  end

  test "a range needs its bounds and a sex there is" do
    glucose = { analyte: "Glucose", unit: "mg/dL" }
    assert_match "no range found in \"soon\"", told_about("set_range", **glucose, range_text: "soon")
    assert_match "sex must be one of", told_about("set_range", **glucose, low: 70, high: 99, sex: "robot")
    assert_match "\"seventy\" is not a number", told_about("set_range", **glucose, low: "seventy")
    assert_match "not understood: mood", told_about("set_range", **glucose, low: 70, high: 99, mood: "calm")
  end

  test "a repeat is one there is, and only what repeats ends, never before it started" do
    one_off = Task.create!(profile: @alice, starts_on: Date.new(2026, 10, 1), title: "Call the bank")
      .occurrence_on(Date.new(2026, 10, 1)).tap(&:save!)
    weekly = events(:water_the_plants).occurrence_on(Date.new(2026, 3, 16)).tap(&:save!)
    repeat = ->(day, recurrence) { told_about("update", type: "task", ref: day.id, recurrence: recurrence) }

    assert_match "repeat must be one of", repeat.(weekly, { frequency: "fortnightly" })
    assert_match "it doesn't repeat, so it can't end", repeat.(one_off, { ends: "2026-12-01" })
    assert_match "so it can't end before that", repeat.(weekly, { ends: "2020-01-01" })
    assert_match "times are only for a medication", repeat.(weekly, { times_of_day: [ "08:00" ] })
    assert_match "only calendar items repeat", told_about("update", type: "recipe", ref: recipes(:roast_chicken).id, recurrence: { frequency: "weekly" })
  end

  test "a meal's recipes are the user's, and what is taken off is on it" do
    supper = meal_on(@alice, Date.new(2026, 10, 7), recipes: [ recipes(:roast_chicken) ])
    assert_match "no recipe named \"Moon cake\"", told_about("update", type: "meal", ref: supper.id, recipes: [ "Moon cake" ])
    Recipe.create!(profile: @alice, name: "Pesto")
    assert_match "this meal doesn't have \"Pesto\"", told_about("update", type: "meal", ref: supper.id, remove_recipes: [ { name: "Pesto" } ])
  end

  test "deleting a repeating item's saved days says the series keeps repeating; too many at once is refused, deleted or done" do
    bins = weekly_event(profile: @alice, type: "Task", starts_on: Date.new(2026, 10, 5), title: "Bins")
    [ 5, 12 ].each { day!(bins, date: Date.new(2026, 10, _1)) }
    assert_match "the series (event_id #{bins.id}) keeps repeating",
                 told_about("delete", type: "task", all: true, query: "Bins", date_from: "2026-10-01", date_to: "2026-10-31")

    30.times { |i| day = Date.new(2026, 11, 1) + i; day!(Task.create!(profile: @alice, starts_on: day, title: "Chore #{i}"), date: day) }
    november = { all: true, query: "Chore", date_from: "2026-11-01", date_to: "2026-11-30" }
    assert_match "more than 25 records match", told_about("delete", type: "task", **november)
    assert_match "more than 25 items match", told_about("complete", type: "task", **november), "never 25 of them done in silence"
  end

  test "a merge is of two analytes, both named, and moves the values, the free ranges and the name" do
    assert_match "merge is only for analytes", told_about("merge", type: "task", ref: @task.id, into: "x")
    assert_match "say which analyte (into)", told_about("merge", type: "analyte", ref: analytes(:glucose).id)

    sugar = Analyte.create!(profile: @alice, name: "Blood sugar")
    lab_result!(profile: @alice, date: Date.new(2026, 10, 1), values: { "Blood sugar" => "90" })
    ReferenceRange.create!(analyte: sugar, unit: units(:mgdl), low: 60, high: 100) # glucose already has this one
    ReferenceRange.create!(analyte: sugar, unit: units(:kg), low: 1, high: 2)
    assert_match "Glucose already has a reference range for mg/dL (any)", told_about("merge", type: "analyte", ref: sugar.id, into: "glucose")

    merge = { op: "merge", type: "analyte", ref: sugar.id, fields: { into: analytes(:glucose).id.to_s } }
    data = submit_changes(@chat, [ merge ], confirm: true)[:data]
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(data[:change_set_id]), confirmed: true)
    assert_not Analyte.exists?(sugar.id)
    assert analytes(:glucose).aliases.exists?(name: "Blood sugar")
    assert_equal [ units(:kg), units(:mgdl) ].map(&:id).sort, analytes(:glucose).reference_ranges.where(sex: :any).pluck(:unit_id).sort
  end

  test "a dose by its series, day and time; the latest when none is named, said so; a partner's items one at a time" do
    twice = timed_medication!(profile: @alice, starts_on: Date.current - 3, times: %w[08:00 20:00]).event
    told_about("complete", type: "medication", event_id: twice.id, date: Date.current.iso8601, time: "20:00")
    assert_equal [ "20:00" ], twice.occurrences.completed.where(date: Date.current).map(&:time_string)

    appointment!(profile: @alice, date: Date.current - 1)
    assert_match "assumed the most recent appointment", told_about("complete", type: "appointment")

    bob = profiles(:bob)
    link!(bob, @alice)
    2.times { |i| day!(Task.create!(profile: bob, starts_on: Date.current + i, title: "Bob's chore #{i}"), date: Date.current + i) }
    assert_match "has to OK changes to their tasks: ask about one at a time",
                 told_about("complete", type: "task", all: true, query: "chore", date_from: Date.current.iso8601,
                                        date_to: (Date.current + 1).iso8601)
  end

  test "a call with nothing in it, and one where a partner's item waits while the rest is saved, say so" do
    assert_match "Nothing to change was given", told

    bob = profiles(:bob)
    link!(bob, @alice)
    bobs = day!(Task.create!(profile: bob, starts_on: Date.current, title: "Bob's chore"), date: Date.current)
    mine = day!(Task.create!(profile: @alice, starts_on: Date.current, title: "Alice's chore"), date: Date.current)
    result = submit_changes(@chat, [ { op: "complete", type: "task", ref: bobs.id }, { op: "complete", type: "task", ref: mine.id } ])
    assert_match "The rest is saved. NOT SAVED: #{bob.display_name} was asked to OK the change to their item", result.dig(:data, :next)
    assert_predicate mine.reload, :completed?
    assert_not bobs.reload.completed?
  end

  test "a range given without its unit takes the one its values use" do
    report = lab_result!(profile: @alice, date: Date.new(2026, 10, 1))
    unit = Unit.find_or_create_by_name("ng/mL", household_id: @alice.household_id)
    report.lab_test_result_entries.create!(analyte: Analyte.create!(profile: @alice, name: "Ferritin"), unit: unit, value: "40")
    told_about("set_range", analyte: "Ferritin", low: 30, high: 400)
    assert_equal "ng/mL", ReferenceRange.joins(:analyte).find_by!(analytes: { name: "Ferritin", profile_id: @alice.id }).unit.name
  end

  test "a new purchase, meal or dose names what exists, and a range has bounds" do
    assert_match "ingredient_purchase.ingredient_name", told_about("create", type: "ingredient_purchase", quantity: 1)
    assert_match "no recipe named \"Moon cake\"", told_about("create", type: "meal", date: "today", recipes: [ "Moon cake" ])
    assert_match "medication.uses",
                 told_about("create", type: "medication", name: "Ferrous sulphate", date: "today", kind: "pill",
                                      uses: [ { supply: "Unobtainium", quantity: 1 } ])
    assert_match "no range found;", told_about("set_range", analyte: "Glucose", unit: "mg/dL")
  end

  test "\"the dentist's done\" with several dentists is the one due today, saved on the way" do
    weekly = series!("Appointment", profile: @alice, starts_on: Date.current, title: "Dentist", rrule: "FREQ=WEEKLY", kind: :medical)
    appointment!(profile: @alice, date: Date.current - 3, title: "Dentist")
    assert_match "picked the one due today", told_about("complete", type: "appointment", ref: "dentist")
    assert_predicate weekly.occurrences.find_by!(date: Date.current), :completed?
  end

  test "supplies sent as a new, unnamed medication point at the one that repeats" do
    series!("Medication", profile: @alice, starts_on: Date.current - 7, title: "Cobalamin", rrule: "FREQ=WEEKLY",
                          kind: :injection, area: :arm, side: :left)
    supply_purchase!(profile: @alice, name: "Needles")
    assert_match "call set_dose_supplies with medication", told_about("create", type: "medication", date: "today", uses: NEEDLE)
  end
end
