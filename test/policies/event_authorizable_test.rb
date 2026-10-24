# frozen_string_literal: true

require "test_helper"

# What a linked housemate may do with someone's days, per their grants —
# and what an explicit share still allows.
class EventAuthorizableTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @task = occurrences(:groceries_due) # Alice's
  end

  def policy(user, record) = Pundit.policy!(user, record)
  def allowed?(user, record, query) = policy(user, record).public_send(query)

  test "a day resolves to its kind's policy" do
    assert_instance_of OccurrencePolicy, policy(@alice, @task)
    assert_instance_of TransactionOccurrencePolicy, policy(@alice, occurrences(:electricity_due))
  end

  test "without a link someone else's task is out of reach" do
    %i[show? edit? update? change_status? destroy?].each do |query|
      assert_not allowed?(@bob, @task, query), query
    end
    assert_not Event.accessible_by(@bob).exists?(@task.event_id)
  end

  test "a pending link gives nothing" do
    Link.create!(requester: @alice, addressee: @bob)

    assert_not Event.accessible_by(@bob).exists?(@task.event_id)
    assert_not allowed?(@bob, @task, :show?)
  end

  test "a link lets the partner see and, by default, ask for everything" do
    link!(@alice, @bob)

    assert Event.accessible_by(@bob).exists?(@task.event_id)
    assert Occurrence.accessible_by(@bob).exists?(@task.id)
    assert allowed?(@bob, @task, :show?)
    %i[update? change_status? destroy?].each do |query|
      assert allowed?(@bob, @task, query), query
      assert policy(@bob, @task).needs_approval?(query), query
    end
    assert_not policy(@alice, @task).needs_approval?(:update?), "the owner never asks"
  end

  test "on is allowed without asking, off is refused" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :on, delete: :off)

    assert allowed?(@bob, @task, :update?)
    assert_not policy(@bob, @task).needs_approval?(:update?)
    assert_not allowed?(@bob, @task, :destroy?)
  end

  test "read off hides that kind only" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", read: :off)

    assert_not Event.accessible_by(@bob).exists?(@task.event_id)
    assert_not allowed?(@bob, @task, :show?)
    assert_not allowed?(@bob, @task, :update?)
    assert Event.accessible_by(@bob).exists?(events(:electricity_bill).id)
  end

  test "grants go one way: the owner's grant decides" do
    link!(@alice, @bob)
    grant(@bob, @alice, "Task", write: :on)

    assert policy(@bob, @task).needs_approval?(:update?), "Bob's grant to Alice says nothing about Alice's tasks"
  end

  test "a new series on a partner's calendar needs their create grant" do
    link!(@alice, @bob)
    day = Task.new(profile: @alice, starts_on: Date.current, title: "x").occurrence_on(Date.current)

    assert allowed?(@bob, day, :create?)
    assert policy(@bob, day).needs_approval?(:create?)
    grant(@alice, @bob, "Task", create: :off)
    Links::Permissions.reset!
    assert_not allowed?(@bob, day, :create?)
    assert_not allowed?(profiles(:carol), day, :create?)
    assert allowed?(@alice, day, :create?), "one's own calendar"
    assert_not policy(@alice, day).needs_approval?(:create?)
  end

  test "a link gives nothing but adding on a series not saved yet" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :on, delete: :on)
    day = Task.new(profile: @alice, starts_on: Date.current, title: "x").occurrence_on(Date.current)

    assert allowed?(@bob, day, :create?)
    assert_not allowed?(@bob, day, :update?)
    assert_not allowed?(@bob, day, :destroy?)
  end

  test "an explicit share still edits without asking" do
    link!(@alice, @bob)
    @task.event.event_shares.create!(profile: @bob)
    @task.event.reload

    assert allowed?(@bob, @task, :update?)
    assert_not policy(@bob, @task).needs_approval?(:update?)
  end

  test "a collection share edits without asking too" do
    day = events(:prescription).occurrence_on(Date.new(2026, 3, 2))

    assert allowed?(@bob, day, :show?)
    assert allowed?(@bob, day, :update?)
    assert_not allowed?(profiles(:carol), day, :show?)
  end

  test "a shared transaction stays read-only; a linked one follows the grant; a counterparty only reads" do
    transaction = occurrences(:electricity_due)
    transaction.event.event_shares.create!(profile: @bob)
    transaction.event.reload
    assert allowed?(@bob, transaction, :show?)
    assert_not allowed?(@bob, transaction, :update?)

    link!(@alice, @bob)
    grant(@alice, @bob, "Transaction", write: :on)
    assert allowed?(@bob, transaction, :update?)
    assert_not policy(@bob, transaction).needs_approval?(:update?)

    paid = transfer!(payer: @alice, counterparty: profiles(:carol), date: Date.current, cents: 100)
    assert allowed?(profiles(:carol), paid, :show?)
    assert_not allowed?(profiles(:carol), paid, :update?)
    assert_not allowed?(profiles(:carol), paid, :destroy?)
    assert allowed?(@alice, paid, :destroy?)
  end

  test "one row per series even through a share, a collection share and a link" do
    link!(@alice, @bob)
    @task.event.event_shares.create!(profile: @bob)

    ids = Event.accessible_by(@bob).pluck(:id)
    assert_equal ids.uniq, ids
  end
end
