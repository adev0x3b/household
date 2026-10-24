# frozen_string_literal: true

require "test_helper"

# How an approved request is carried out: which step runs each kind, that
# it acts on the dose it was asked about, and that nothing is pushed to
# anyone before the decision commits.
class Links::Approvals::ApplyTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "each kind of request has its step, and the assistant's its runner" do
    steps = LinkApproval.action_kinds.keys.to_h { |kind| [ kind, Links::Approvals::Apply.step_for(LinkApproval.new(action_kind: kind, source: :form)) ] }

    assert_equal({ "create" => Links::Approvals::Apply::SaveForm, "update" => Links::Approvals::Apply::SaveForm,
                   "complete" => Links::Approvals::Apply::Completion,
                   "uncomplete" => Links::Approvals::Apply::Completion,
                   "destroy" => Links::Approvals::Apply::Destroy }, steps)
    assert_equal Links::Approvals::OperationRunner, Links::Approvals::Apply.step_for(LinkApproval.new(action_kind: :update, source: :assistant))
  end

  test "a held operation's broadcasts wait for the transaction around the decision" do
    applier = Links::Approvals::OperationRunner::Applier.new
    pushed = false
    applier.defer([ -> { pushed = true } ])

    ActiveRecord::Base.transaction do
      applier.finish
      assert_not pushed, "nothing goes out while the decision may still roll back"
    end

    assert pushed
  end

  # Alice's twice-a-day medication, and Bob asking about tomorrow's evening
  # dose before anyone has touched it.
  def evening_request(kind, scope: nil, **levels)
    alice = profiles(:alice)
    bob = profiles(:bob)
    link!(alice, bob)
    grant(alice, bob, "Medication", **levels)
    @series = series!("Medication", profile: alice, starts_on: Date.current, title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    @tomorrow = Date.current + 1
    evening = @series.occurrence_on(@tomorrow, time: "20:00")
    assert_predicate evening, :new_record?

    Links::Approvals::Hold.call(requester: bob, record: evening, kind: kind, scope: scope)
  end

  def tomorrow = @series.reload.occurrences_between(@tomorrow, @tomorrow).map { [ _1.time_string, _1.status ] }

  test "approving one dose as taken marks that dose alone" do
    approval = evening_request(:complete, write: :ask)
    Links::Approvals::Decide.call(approval, approve: true)

    assert_predicate approval.reload, :approved?
    assert_equal [ [ "08:00", "pending" ], [ "20:00", "completed" ] ], tomorrow
  end

  test "approving the deletion of one dose deletes that dose alone" do
    approval = evening_request(:destroy, delete: :ask)
    Links::Approvals::Decide.call(approval, approve: true)

    assert_predicate approval.reload, :approved?
    assert_equal [ [ "08:00", "pending" ] ], tomorrow
  end

  test "approving the deletion of the whole series deletes every day of it" do
    approval = evening_request(:destroy, scope: "series", delete: :ask)
    Links::Approvals::Decide.call(approval, approve: true)

    assert_predicate approval.reload, :approved?
    assert_not Event.exists?(@series.id)
  end

  test "a dose the series no longer has can't be approved" do
    approval = evening_request(:complete, write: :ask)
    @series.skip!(@tomorrow, time: "20:00")
    Links::Approvals::Decide.call(approval, approve: true)

    assert_predicate approval.reload, :failed?
    assert_predicate approval, :failure_gone?
    assert_equal [ [ "08:00", "pending" ] ], tomorrow
  end

  test "a day marked done on approval is redrawn on the owner's calendar" do
    alice, bob = profiles(:alice), profiles(:bob)
    link!(alice, bob)
    grant(alice, bob, "Task", write: :ask)
    day = task!(profile: alice, date: Date.new(2026, 10, 14), title: "Bins")
    approval = Links::Approvals::Hold.call(requester: bob, record: day, kind: :complete)
    room = "profile_#{alice.id}:2026-10"
    CalendarWatch.watch!(room, "alice's tab")

    pushed = capture_broadcasts(room) { Links::Approvals::Decide.call(approval, approve: true) }

    assert_predicate day.reload, :completed?
    assert(pushed.any? { _1.include?(%(target="day_2026-10-14")) })
  end

  test "a request that no longer saves is reported, and its asker reads why in their own language" do
    approval = evening_request(:complete, write: :ask)
    profiles(:alice).update!(locale: "en")
    profiles(:bob).update!(locale: "it")

    no_longer_saves = ->(_) { raise Links::Approvals::Apply::Failed.new(:changed, "Quantity must be greater than 0") }
    assert_error_reported(Links::Approvals::Apply::Failed) do
      swapping(Links::Approvals::Apply, :call, no_longer_saves) { Links::Approvals::Decide.call(approval, approve: true) }
    end

    assert_predicate approval.reload, :failure_changed?
    notification = Notification.find_by!(profile: profiles(:bob), kind: :approval_failed)
    detail = profiles(:bob).as_viewer { Notifications::Wording.new(notification).detail }
    assert_equal I18n.t("links.approvals.failures.changed", locale: :it), detail
  end
end
