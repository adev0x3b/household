# frozen_string_literal: true

require "test_helper"

# Assistant::ChangeSets::RowTargets: what each row of the chat's change set
# cards opens, read for every card at once.
class Assistant::ChangeSets::RowTargetsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @chat = assistant_chat(@alice)
  end

  # Each in a chat of its own, as two saved cards would be.
  def create_task(title, date)
    chat = assistant_chat(@alice)
    submit_changes(chat, [ { intent: 0, op: "create", type: "task", fields: { title: title, date: date } } ])
    chat.change_sets.sole
  end

  test "saved rows open their records, read in one query for all the cards" do
    sets = [ create_task("Call mum", "2026-09-30"), create_task("Return the library books", "2026-10-01") ]
    assert sets.all?(&:applied?)

    targets = assert_queries_count(2) { Assistant::ChangeSets::RowTargets.load(sets) }

    opened = sets.map { |set| targets.for(set, set.display.first) }
    assert_equal %w[task task], opened.map(&:type)
    titles = opened.map { |target| target.record.event.title }
    assert_equal [ "Call mum", "Return the library books" ], titles
  end

  test "a row of a set in progress opens its draft; one without a review opens nothing" do
    submit_changes(@chat, [ { intent: 0, op: "create", type: "appointment", fields: { provider: "Rossi", date: "2026-09-30" } } ])
    set = @chat.change_sets.order(:id).last
    targets = Assistant::ChangeSets::RowTargets.load(set)

    target = targets.for(set, set.display.first)
    assert_nil target.record
    assert_equal "appointment", target.type
    assert_nil targets.for(set, set.display.first.except("review"))
  end

  test "it reads every kind a saved row can open" do
    assert_equal Assistant::ChangeSets::Review::EDITABLE.sort, Assistant::ChangeSets::RowTargets::SCOPES.keys.sort
  end
end
