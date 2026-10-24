# frozen_string_literal: true

require "test_helper"

# The assistant acting on a linked housemate's item: what their grant says
# "ask" for is sent to them to OK instead of saved, applied as theirs when
# they approve; what it says "no" for is refused.
class Assistant::LinkedChangesTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @task = occurrences(:groceries_due) # a day of Alice's one-off task
    link!(@alice, @bob)
    @chat = assistant_chat(@bob)
    travel_to Time.zone.local(2026, 9, 23, 12)
  end

  teardown { travel_back }

  def change_set(operations)
    Assistant::ChangeSet.current_for(@chat).tap do |set|
      set.merge!(intents: [ "change it" ], operations: operations)
      set.save!
    end
  end

  def rename(title) = [ { "intent" => 0, "op" => "update", "type" => "task", "ref" => @task.id, "fields" => { "title" => title } } ]

  test "a change Alice must OK is asked for, not saved, and saved as hers when she approves" do
    set = change_set(rename("Buy groceries and bread"))
    result = Assistant::ChangeSets::Compiler.call(set)
    op = result.operations.sole
    assert_predicate op, :held?
    assert_equal "Ask Alice: Update Buy groceries on March 2, 2026", op.summary
    assert_equal "Alice", op.to_result[:needs_approval_from]
    assert_equal :confirm, result.status, "Alice will read the request, so it waits for Bob's button first"

    Assistant::ChangeSets::Applier.call(set, confirmed: true)
    assert_equal "Buy groceries", @task.reload.title
    assert_equal "asked", set.reload.display.sole["status"]

    approval = LinkApproval.sole
    assert_predicate approval, :from_assistant?
    assert_equal [ { "attribute" => "title", "from" => "Buy groceries", "to" => "Buy groceries and bread" } ], approval.preview

    Links::Approvals::Decide.call(approval, approve: true)
    assert_predicate approval.reload, :approved?, approval.failure.to_s
    assert_equal "Buy groceries and bread", @task.reload.title
  end

  test "what Alice is asked shows each field as she has it and as it would be" do
    set = change_set([ { "intent" => 0, "op" => "update", "type" => "task", "ref" => @task.id, "fields" => { "date" => "2026-03-05", "priority" => "high" } } ])
    Assistant::ChangeSets::Applier.call(set, confirmed: true)

    preview = LinkApproval.sole.preview.index_by { |row| row["attribute"] }
    assert_equal [ "2026-03-02", "2026-03-05" ], preview["date"].values_at("from", "to")
    assert_equal "high", preview["priority"]["to"]
  end

  test "undo takes the request back while it waits" do
    set = change_set(rename("Later"))
    Assistant::ChangeSets::Applier.call(set, confirmed: true)

    Assistant::ChangeSets::Undoer.call(set.reload)
    assert_predicate LinkApproval.sole, :withdrawn?
  end

  test "once answered it can't be undone" do
    set = change_set(rename("Later"))
    Assistant::ChangeSets::Applier.call(set, confirmed: true)
    Links::Approvals::Decide.call(LinkApproval.sole, approve: false)

    error = assert_raises(Assistant::ChangeSets::Undoer::CannotUndo) { Assistant::ChangeSets::Undoer.call(set.reload) }
    assert_equal :decided, error.key
  end

  test "with write on it is saved at once; with it off it is refused" do
    grant(@alice, @bob, "Task", write: :on)
    set = change_set(rename("Straight in"))
    Assistant::ChangeSets::Applier.call(set, confirmed: true)
    assert_equal "Straight in", @task.reload.title
    assert_empty LinkApproval.all

    grant(@alice, @bob, "Task", write: :off)
    Links::Permissions.reset!
    other = Assistant::ChangeSet.current_for(@chat).tap { |s| s.merge!(intents: [ "again" ], operations: rename("Nope")); s.save! }
    refused = Assistant::ChangeSets::Compiler.call(other).operations.sole
    assert_includes refused.problems, "not found, or not the user's to change"
    assert_not refused.held?
  end

  test "marking it done and deleting it are asked for too" do
    set = change_set([ { "intent" => 0, "op" => "complete", "type" => "task", "ref" => @task.id } ])
    Assistant::ChangeSets::Applier.call(set)
    assert_predicate @task.reload, :pending?
    assert_equal "complete", LinkApproval.last.action_kind

    Links::Approvals::Decide.call(LinkApproval.last, approve: true)
    assert_predicate @task.reload, :completed?
  end
end
