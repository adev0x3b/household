# frozen_string_literal: true

require "test_helper"

# Change sets without a model: what the write tools hand the server is
# compiled, applied atomically, and undone.
class Assistant::ChangeSetsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @chat = assistant_chat(@alice)
    travel_to Time.zone.local(2026, 9, 23, 12)
  end

  teardown { travel_back }

  def change_set(intents, operations, chat: @chat)
    Assistant::ChangeSet.current_for(chat).tap do |set|
      set.merge!(intents: intents, operations: operations)
      set.save!
    end
  end

  def compile(set) = Assistant::ChangeSets::Compiler.call(set)
  def apply(set, **) = Assistant::ChangeSets::Applier.call(set, **)
  def ranges_of(name) = ReferenceRange.joins(:analyte).where(analytes: { profile_id: @alice.id }).where("LOWER(analytes.name) = ?", name.downcase)

  REPORT_AND_RANGES = [
    { "intent" => 0, "op" => "create", "type" => "lab_test_result",
      "fields" => { "date" => "a week ago", "values" => { "Cobalamin" => "250", "Homocysteine" => "0.8", "Calcium" => "3", "Vitamin D" => "20" } } },
    { "intent" => 1, "op" => "set_range", "fields" => { "analyte" => "Cobalamin", "unit" => "pg/mL", "range_text" => "150 low 250 high 80 critically low 300 critically high" } },
    { "intent" => 1, "op" => "set_range", "fields" => { "analyte" => "Vitamin D", "unit" => "ng/mL", "range_text" => "good between 20 and 50" } },
    { "intent" => 1, "op" => "set_range", "fields" => { "analyte" => "Homocysteine", "unit" => "ng/mL", "range_text" => "below 0.8 is good, 1.4 is critically high" } },
    { "intent" => 1, "op" => "set_range", "fields" => { "analyte" => "Calcium", "unit" => "mg/dL", "range_text" => "between 8.5 and 10" } }
  ].freeze

  test "the report and its ranges in one message are saved together, values flagged" do
    set = change_set([ "record the lab report", "save the doctor's ranges" ], REPORT_AND_RANGES)

    result = compile(set)
    assert_equal :ready, result.status, result.operations.map(&:to_result).inspect

    apply(set)
    lab = days_of(LabTestResult, @alice).last
    assert_equal Date.new(2026, 9, 16), lab.date
    assert_predicate lab, :completed?, "a test done last week is saved as done"
    values = Assistant::Resources.lab_values(lab)
    assert_includes values, "Calcium: 3 mg/dL (low)"
    assert_includes values, "Cobalamin: 250 pg/mL (normal)"
    assert_equal 1, Analyte.where(profile: @alice, name: "Cobalamin").count, "one analyte, shared by the value and its range"
    assert_predicate set.reload, :applied?
  end

  test "a later call merges into the open set" do
    set = change_set([ "record the lab report" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result", "fields" => { "values" => { "TSH" => "2.1" } } } ])
    assert_equal [ "lab_test_result.date" ], compile(set).operations.first.missing

    set = change_set([ "record the lab report" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result", "fields" => { "date" => "yesterday" } } ])

    assert_equal 1, set.operations.size
    assert_equal :ready, compile(set).status
  end

  test "a follow-up without a title still merges into the titled item; a different item doesn't" do
    change_set([ "report" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result", "fields" => { "title" => "B12 panel", "values" => { "TSH" => "2" } } } ])
    set = change_set([ "report" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result", "fields" => { "date" => "yesterday" } } ])
    assert_equal 1, set.operations.size

    set = change_set([ "report" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result", "fields" => { "title" => "Thyroid panel" } } ])
    assert_equal 2, set.operations.size
  end

  test "sets in progress expire and stay in their own chat" do
    change_set([ "x" ], [ { "intent" => 0, "op" => "create", "type" => "task", "fields" => { "title" => "Water plants" } } ])
    other_chat = assistant_chat(@alice)
    assert_empty Assistant::ChangeSet.current_for(other_chat).operations

    travel 25.hours
    assert_empty Assistant::ChangeSet.current_for(@chat).operations
  end

  test "references by words, with dates; ambiguity comes back with candidates" do
    first = lab_result!(profile: @alice, date: Date.new(2026, 9, 16), values: { "Calcium" => "300" })
    lab_result!(profile: @alice, date: Date.new(2026, 9, 20))

    resolver = Assistant::ChangeSets::Resolver.new(@alice)
    assert_equal first, resolver.resolve("lab_test_result", "the lab report from a week ago").record
    assert_equal 2, resolver.resolve("lab_test_result", "the panel").candidates.size
    assert resolver.resolve("lab_test_result", nil).assumed

    set = change_set([ "fix calcium" ], [ { "intent" => 0, "op" => "update", "type" => "lab_test_result", "ref" => "the lab report from a week ago",
                                            "fields" => { "values" => { "Calcium" => "3 mg/dL" } } } ])
    apply(set)
    assert_equal "3", first.lab_test_result_entries.reload.sole.value
  end

  test "several things bought in one create become one purchase each" do
    set = change_set([ "log purchases" ], [ { "intent" => 0, "op" => "create", "type" => "supply_purchase",
                                              "fields" => { "items" => "vial of vitamins, needles and syringes", "therapy_id" => collections(:b12).id } } ])
    result = compile(set)

    assert_equal 3, result.operations.size
    assert_equal([ "adds the new supply vial of vitamins", "adds the new supply needles", "adds the new supply syringes" ],
                 result.operations.map { |op| op.notes.grep(/supply/).first })
  end

  test "ranges filed under a lab result become range operations" do
    set = change_set([ "record", "ranges" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result",
                                                 "fields" => { "date" => "yesterday", "Calcium" => "3 mg/dL",
                                                               "reference_ranges" => { "Calcium" => "8.5-10 mg/dL" } } } ])
    result = compile(set)

    assert_equal %w[create set_range], result.operations.map(&:op)
    assert_equal([ 0, 0 ], result.operations.map { |op| op.intent.to_i })
  end

  test "deleting waits for the user's button and can't be undone" do
    appointment = appointment!(profile: @alice, date: Date.new(2026, 9, 25))
    set = change_set([ "delete all appointments" ], [ { "intent" => 0, "op" => "delete", "type" => "appointment", "fields" => { "all" => true } } ])

    assert_equal :confirm, compile(set).status
    assert_raises(Assistant::ChangeSets::Applier::NotReady) { apply(set) }

    apply(set, confirmed: true)
    assert_not Occurrence.exists?(appointment.id)
    assert_not Event.exists?(appointment.event_id), "a one-off goes with its day"
    assert_not set.reload.undoable
    assert_raises(Assistant::ChangeSets::Undoer::CannotUndo) { Assistant::ChangeSets::Undoer.call(set) }
  end

  test "a change someone else will see waits for the button, and the card says who" do
    bob = profiles(:bob)
    set = change_set([ "Bob paid me 50" ], [ { "intent" => 0, "op" => "create", "type" => "transaction",
                                               "fields" => { "title" => "Rent share", "amount" => 50, "kind" => "income", "category" => "housing",
                                                             "payment_method" => "cash", "counterparty_profile_id" => bob.id, "date" => "today" } } ])
    result = compile(set)
    op = result.operations.sole

    assert_equal :confirm, result.status
    assert_equal [ "Bob" ], op.to_result[:seen_by]
    assert_includes op.notes, "Bob will see this: it waits for the user's Apply button."
    set.show!(result)
    assert_equal [ "Bob" ], set.reload.seen_by
    assert_raises(Assistant::ChangeSets::Applier::NotReady) { apply(set) }

    apply(set, confirmed: true)
    assert Event.accessible_by(bob).exists?(Transaction.find_by!(title: "Rent share").id)
  end

  test "renaming a shared list waits for the button; marking a shared item done doesn't, since it carries no words" do
    bob = profiles(:bob)
    list = grocery_lists(:weekly_shop)
    rename = change_set([ "rename the list" ], [ { "intent" => 0, "op" => "update", "type" => "grocery_list", "ref" => list.id,
                                                   "fields" => { "name" => "Saturday shop" } } ])
    assert_equal :confirm, compile(rename).status
    assert_equal [ "Bob" ], compile(rename).operations.sole.to_result[:seen_by]
    assert_equal "Weekly shop", list.reload.name

    visit = appointment!(profile: @alice, date: Date.new(2026, 9, 23))
    Shares::Create.call(visit.event, with: bob, by: @alice)
    done = change_set([ "visit done" ], [ { "intent" => 0, "op" => "complete", "type" => "appointment", "ref" => visit.id } ], chat: assistant_chat(@alice))
    result = compile(done)
    assert_equal :ready, result.status
    assert_nil result.operations.sole.to_result[:seen_by]
  end

  test "a possible duplicate waits for confirmation unless already accepted" do
    appointment!(profile: @alice, date: Date.new(2026, 10, 2), counterpart: "Moretti")
    set = change_set([ "book Moretti" ], [ { "intent" => 0, "op" => "create", "type" => "appointment",
                                             "fields" => { "counterpart" => "Moretti", "date" => "this friday", "time" => "11:00" } } ])
    result = compile(set)
    assert_equal :confirm, result.status

    set.update!(acknowledged_warnings: result.operations.flat_map(&:warning_keys))
    assert_equal :ready, compile(set).status
  end

  test "undo reverts a purchase, its cost and a supply it added" do
    set = change_set([ "log purchase" ], [ { "intent" => 0, "op" => "create", "type" => "supply_purchase",
                                             "fields" => { "supply" => "Pen needles 4mm", "quantity" => 100, "amount" => "12", "payment_method" => "card" } } ])
    apply(set)
    assert Supply.exists?(name: "Pen needles 4mm")

    Assistant::ChangeSets::Undoer.call(set)

    assert_not Supply.exists?(name: "Pen needles 4mm")
    assert_equal 0, SupplyPurchase.where(profile: @alice).joins(:supply).where(supplies: { name: "Pen needles 4mm" }).count
    assert_predicate set.reload, :undone?
  end

  test "undo reverts an update, a completion with its fee, and ranges" do
    lab = lab_result!(profile: @alice, date: Date.new(2026, 9, 16), values: { "Calcium" => "300" })
    visit = appointment!(profile: @alice, date: Date.new(2026, 9, 23), counterpart: "Moretti")
    fee = expense!(profile: @alice, date: Date.new(2026, 9, 23), cents: 5000, status: :pending, about: visit)
    Assistant::ChangeSets::Applier.call(change_set([ "range" ], [ { "intent" => 0, "op" => "set_range", "fields" => { "analyte" => "Calcium", "unit" => "mg/dL", "low" => 8, "high" => 11 } } ]))
    @chat = assistant_chat(@alice)

    set = change_set([ "fix", "done", "range" ], [
                       { "intent" => 0, "op" => "update", "type" => "lab_test_result", "ref" => lab.id, "fields" => { "values" => { "Calcium" => "3 mg/dL" } } },
                       { "intent" => 1, "op" => "complete", "type" => "appointment", "ref" => visit.id },
                       { "intent" => 2, "op" => "set_range", "fields" => { "analyte" => "Calcium", "unit" => "mg/dL", "range_text" => "8.5-10" } }
                     ])
    apply(set)
    assert visit.reload.completed? && fee.reload.completed?

    Assistant::ChangeSets::Undoer.call(set)

    assert_equal "300", lab.lab_test_result_entries.reload.sole.value
    assert_predicate visit.reload, :pending?
    assert_predicate fee.reload, :pending?
    assert_equal [ 8.0, 11.0 ], ranges_of("Calcium").sole.values_at(:low, :high).map(&:to_f)
  end

  test "undo refuses when a record was changed afterwards" do
    set = change_set([ "task" ], [ { "intent" => 0, "op" => "create", "type" => "task", "fields" => { "title" => "Repot cactus", "date" => "tomorrow" } } ])
    apply(set)
    Task.find_by(title: "Repot cactus").tap { |task| travel(1.minute) { task.update!(title: "Repot both cacti") } }
    assert_predicate days_of(Task, @alice).joins(:event).where(events: { title: "Repot both cacti" }), :exists?, "its day was saved with the series"

    error = assert_raises(Assistant::ChangeSets::Undoer::CannotUndo) { Assistant::ChangeSets::Undoer.call(set) }
    assert_match "changed afterwards", error.message
  end

  test "undo refuses when only a kind's own field was changed afterwards" do
    set = change_set([ "task" ], [ { "intent" => 0, "op" => "create", "type" => "task", "fields" => { "title" => "Repot cactus", "date" => "tomorrow" } } ])
    apply(set)
    Task.find_by(title: "Repot cactus").tap { |task| travel(1.minute) { task.details.update!(priority: :urgent) } }

    error = assert_raises(Assistant::ChangeSets::Undoer::CannotUndo) { Assistant::ChangeSets::Undoer.call(set) }
    assert_match "changed afterwards", error.message
    assert Task.exists?(title: "Repot cactus"), "the later edit is kept"
  end

  test "another profile's records can't be referenced" do
    theirs = appointment!(profile: profiles(:carol), date: Date.new(2026, 9, 25))
    set = change_set([ "done" ], [ { "intent" => 0, "op" => "complete", "type" => "appointment", "ref" => theirs.id } ])

    result = compile(set)
    assert_equal :invalid, result.operations.sole.status
    assert_match "no appointment with id #{theirs.id}", result.operations.sole.problems.sole
  end

  test "the per-turn context shows only this chat's changes in progress" do
    change_set([ "book" ], [ { "intent" => 0, "op" => "create", "type" => "appointment", "fields" => { "counterpart" => "Rossi", "date" => "tomorrow" } } ]).tap do |set|
      set.show!(compile(set))
    end

    assert_match "Changes in progress", Assistant::Context.new(@chat).to_prompt
    assert_match "Appointment with Rossi", Assistant::Context.new(@chat).to_prompt
    assert_no_match "Changes in progress", Assistant::Context.new(assistant_chat(@alice)).to_prompt
  end

  test "one sentence of ranges on a lab result is split by the analytes it names" do
    set = change_set([ "record with ranges" ], [ { "intent" => 0, "op" => "create", "type" => "lab_test_result",
                                                   "fields" => { "date" => "yesterday", "values" => { "Cobalamin" => "250 pg/mL", "Vitamin D" => "20 ng/mL" },
                                                                 "reference_range" => "Cobalamin in pg/mL 150 low 250 high 80 critically low. Vitamin D is good between 20 and 50" } } ])
    result = compile(set)

    assert_equal :ready, result.status, result.operations.map(&:to_result).inspect
    assert_equal [ "Cobalamin (pg/mL): low 150, high 250, critically low at 80", "Vitamin D (ng/mL): low 20, high 50" ],
                 result.operations.drop(1).map(&:label)
  end

  test "a generic ref deletes everything of that type; complete finds the visit from its fields" do
    appointment!(profile: @alice, date: Date.new(2026, 9, 25))
    appointment!(profile: @alice, date: Date.new(2026, 10, 2))
    delete = compile(change_set([ "delete" ], [ { "intent" => 0, "op" => "delete", "type" => "appointment", "ref" => "all my appointments" } ]))
    assert_equal Assistant::Resources.fetch("appointment").accessible(@alice).count, delete.operations.sole.label.scan(/on /).size

    @chat = assistant_chat(@alice)
    visit = appointment!(profile: @alice, date: Date.new(2026, 9, 23), counterpart: "Moretti")
    done = compile(change_set([ "done" ], [ { "intent" => 0, "op" => "complete", "type" => "appointment", "fields" => { "counterpart" => "Moretti", "date" => "today" } } ]))
    assert_equal :ready, done.status, done.operations.map(&:to_result).inspect
    Assistant::ChangeSets::Applier.call(@chat.change_sets.last)
    assert_predicate visit.reload, :completed?
  end

  test "a draft in progress is the first day of its new series, its fee answering for itself" do
    set = change_set([ "book" ], [ { "intent" => 0, "op" => "create", "type" => "appointment",
                                     "fields" => { "counterpart" => "Rossi", "date" => "2026-10-05", "amount" => "40", "payment_method" => "card" } } ])
    draft = Assistant::ChangeSets::Review.draft_record(set, 0)

    assert_predicate draft, :new_record?
    assert_equal [ Date.new(2026, 10, 5), "Rossi" ], [ draft.date, draft.details.counterpart ]
    assert_equal [ 40, "card" ], [ draft.cost.details.amount.to_i, draft.cost.details.payment_method ]
    assert_equal 0, Appointment.where(profile: @alice).joins(:details).where(appointment_details: { counterpart: "Rossi" }).count
  end

  test "a saved row knows its day, not the fee that came with it" do
    entries = [ { "kind" => "created", "model" => "Occurrence", "id" => 1, "type" => "Appointment" },
                { "kind" => "created", "model" => "Occurrence", "id" => 2, "type" => "Transaction" } ]

    assert_equal({ "model" => "Occurrence", "id" => 1 }, Assistant::ChangeSets::Review.row_record(entries))
    assert_equal "lab_test_result", Assistant::ChangeSets::Review.type_of(occurrences(:bloodwork_due))
    assert_equal "collection", Assistant::ChangeSets::Review.type_of(collections(:b12))
  end

  test "re-creating what already exists that day points at mark_done/update_record; 'credit card' is card" do
    visit = appointment!(profile: @alice, date: Date.new(2026, 9, 25), counterpart: "Moretti")
    set = change_set([ "done" ], [ { "intent" => 0, "op" => "create", "type" => "appointment",
                                     "fields" => { "provider" => "Moretti", "date" => "2026-09-25", "time" => "11:00" } } ])
    op = compile(set).operations.sole
    assert_equal :invalid, op.status
    assert_match "use mark_done with ref #{visit.id}", op.problems.sole
    assert_match "use update_record with ref #{visit.id}", op.problems.sole

    assert_equal "card", Assistant::Normalize.payment("Credit card")
    assert_equal "bank_transfer", Assistant::Normalize.payment("bonifico")
  end

  def submit(operations) = Assistant::ChangeSets::Submit.call(chat: @chat, operations: operations)

  test "Apply deletes what the card listed, not what matches by the time it is pressed" do
    listed = [ appointment!(profile: @alice, date: Date.new(2026, 9, 25)), appointment!(profile: @alice, date: Date.new(2026, 10, 2)) ]
    asked = submit([ { op: "delete", type: "appointment", fields: { all: true } } ])
    assert_equal "waiting_for_user", asked[:status]
    later = appointment!(profile: @alice, date: Date.new(2026, 10, 9))

    apply(Assistant::ChangeSet.find(asked[:change_set_id]), confirmed: true)
    listed.each { |day| assert_not Occurrence.exists?(day.id) }
    assert Occurrence.exists?(later.id), "what came after the card was shown stays"
  end

  test "Apply refuses, and changes nothing, when something the card listed went meanwhile" do
    kept = appointment!(profile: @alice, date: Date.new(2026, 9, 25))
    gone = appointment!(profile: @alice, date: Date.new(2026, 10, 2))
    set = Assistant::ChangeSet.find(submit([ { op: "delete", type: "appointment", fields: { all: true } } ])[:change_set_id])
    Occurrences::Destroy.call(gone, by: @alice, scope: "series")

    assert_raises(Assistant::ChangeSets::Applier::NotReady) { apply(set, confirmed: true) }
    assert Occurrence.exists?(kept.id)
    assert_predicate set.reload, :awaiting_confirmation?
  end

  test "a set pressed twice, from two tabs, is applied once" do
    recipe = Recipe.create!(profile: @alice, name: "Pesto")
    asked = submit([ { op: "share", type: "recipe", ref: recipe.id, fields: { with: profiles(:bob).first_name } } ])
    assert_equal "waiting_for_user", asked[:status], asked.inspect
    first_tab, second_tab = 2.times.map { Assistant::ChangeSet.find(asked[:change_set_id]) }

    apply(first_tab, confirmed: true)
    assert_raises(Assistant::ChangeSets::Applier::NotReady) { apply(second_tab, confirmed: true) }
    assert_equal 1, recipe.recipe_shares.count
    assert_predicate second_tab.reload, :applied?
  end

  test "undo keeps a series it created once one of its days was done afterwards" do
    saved = submit([ { op: "create", type: "task", fields: { title: "Take out the recycling", date: "tomorrow", recurrence: { frequency: "weekly" } } } ])
    assert_equal "saved", saved[:status], saved.inspect
    event = Task.find_by!(title: "Take out the recycling")
    travel(1.week) { day!(event, date: Date.new(2026, 10, 1), status: :completed) }

    error = assert_raises(Assistant::ChangeSets::Undoer::CannotUndo) { Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(saved[:change_set_id])) }
    assert_equal :changed_since, error.key
    assert_predicate event.reload.occurrences.find_by(date: Date.new(2026, 10, 1)), :completed?, "the day done since is kept"
  end

  test "a day marked done in a set that waits for Apply is the day the card listed" do
    laundry = task!(profile: @alice, date: Date.new(2026, 9, 23))
    recipe = Recipe.create!(profile: @alice, name: "Pesto")
    # A handle ties the set's operations together, so none is saved before the press.
    asked = submit([ { op: "create", type: "task", as: "$bins", fields: { title: "Take out the bins", date: "tomorrow" } },
                     { op: "share", type: "recipe", ref: recipe.id, fields: { with: profiles(:bob).first_name } },
                     { op: "complete", type: "task", ref: laundry.id } ])
    assert_equal "waiting_for_user", asked[:status], asked.inspect

    apply(Assistant::ChangeSet.find(asked[:change_set_id]), confirmed: true)
    assert_predicate laundry.reload, :completed?
  end

  test "a share asks which record, or which housemate, when the words fit several" do
    Recipe.create!(profile: @alice, name: "Pesto genovese")
    rosso = Recipe.create!(profile: @alice, name: "Pesto rosso")
    which_recipe = submit([ { op: "share", type: "recipe", ref: "pesto", fields: { with: profiles(:bob).first_name } } ])
    assert_equal "needs_input", which_recipe[:status], which_recipe.inspect
    assert_equal 2, which_recipe.dig(:changes, 0, :candidates).size
    assert_match "Bob", which_recipe.dig(:changes, 0, :summary)

    which_person = submit([ { op: "share", type: "recipe", ref: rosso.id, fields: { with: "Example" } } ])
    assert_equal "needs_input", which_person[:status], which_person.inspect
    assert_equal %w[Bob Carol], which_person.dig(:changes, 0, :candidates).map { _1[:name].split.first }.sort
  end

  test "a recipe shared by hand while the card waited is shared once" do
    recipe = Recipe.create!(profile: @alice, name: "Pesto")
    asked = submit([ { op: "share", type: "recipe", ref: recipe.id, fields: { with: profiles(:bob).first_name } } ])
    Shares::Create.call(recipe, with: profiles(:bob), by: @alice)

    apply(Assistant::ChangeSet.find(asked[:change_set_id]), confirmed: true)
    assert_equal 1, recipe.recipe_shares.count
  end

  test "a done day to undo is never guessed: several that fit are asked about" do
    task!(profile: @alice, date: Date.new(2026, 9, 21), status: :completed)
    task!(profile: @alice, date: Date.new(2026, 9, 23), status: :completed)

    asked = submit([ { op: "uncomplete", type: "task", ref: "laundry" } ])
    assert_equal "needs_input", asked[:status], asked.inspect
    assert_equal 2, asked.dig(:changes, 0, :candidates).size
  end
end
