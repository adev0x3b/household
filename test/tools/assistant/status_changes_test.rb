# frozen_string_literal: true

require "test_helper"

# mark_done beyond "done": skipped, cancelled, in progress, reopened — and
# many at once. Uses the eval seeds, so these and the eval scenarios share
# their starting states (lib/assistant_eval/seeds.rb).
class Assistant::StatusChangesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12) # a Thursday: an injection is due today
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
  end

  teardown { travel_back }

  def doses = days_of(Medication, @profile)

  # Metformin with breakfast (08:00) and dinner (19:30) every day since Sep 10.
  def metformin = @metformin ||= AssistantEval::Seeds.metformin_twice_daily(@profile).event

  test "a dose of several in a day: the one named by its time, else the next still to take" do
    event = metformin

    result = run_tool(:mark_done, @chat, type: "medication", ref: "metformin today", time: "dinner")
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal([ [ "19:30", "completed" ] ], doses.where(date: Date.new(2026, 9, 24)).map { [ _1.time_string, _1.status ] })
    assert_equal [ "19:30", "dinner" ], result[:data][:saved].first.values_at(:time, :with)

    result = run_tool(:mark_done, @chat, type: "medication", ref: "metformin today")
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "08:00", "19:30" ], doses.where(date: Date.new(2026, 9, 24)).map(&:time_string)
    assert doses.where(date: Date.new(2026, 9, 24)).all?(&:completed?)

    result = run_tool(:mark_done, @chat, type: "medication", ref: "event_id #{event.id} on 2026-09-23 at 8", status: "skipped")
    assert_equal "saved", result[:data][:status], result.inspect
    skipped = event.occurrences.find_by!(date: Date.new(2026, 9, 23), time: "08:00")
    assert_equal "skipped", skipped.status

    result = run_tool(:update_record, @chat, type: "medication", ref: "event_id #{event.id} on 2026-09-23 at breakfast", changes: { "not_taken_reason" => "forgot" })
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "forgot", skipped.reload.skipped_reason

    result = run_tool(:mark_done, @chat, type: "medication", ref: "event_id #{event.id} on 2026-09-22 at dinner", status: "skipped", reason: "refused")
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "skipped", "refused" ], event.occurrences.find_by!(date: Date.new(2026, 9, 22), time: "19:30").values_at(:status, :skipped_reason)
  end

  test "every dose of the week at once counts each dose of a day" do
    metformin

    result = run_tool(:mark_done, @chat, type: "medication", all: true, query: "metformin", date_from: "2026-09-21", date_to: "2026-09-24")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 8, doses.where(status: :completed).count
  end

  test "skipping today's dose saves it as skipped" do
    AssistantEval::Seeds.b12_injection_series(@profile)

    result = run_tool(:mark_done, @chat, type: "medication", ref: "cobalamin today", status: "skipped")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "skipped", doses.find_by(date: Date.new(2026, 9, 24)).status
  end

  test "cancelling an appointment keeps it, cancels its unpaid fee, and Undo brings both back" do
    AssistantEval::Seeds.moretti_oct2_with_fee(@profile)
    appointment = days_of(Appointment, @profile).sole

    result = run_tool(:mark_done, @chat, type: "appointment", ref: "Moretti October 2", status: "cancelled")
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "cancelled", appointment.reload.status
    assert_equal "cancelled", appointment.costs.sole.status

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_equal "pending", appointment.reload.status
    assert_equal "pending", appointment.costs.sole.status
  end

  test "a paid fee stays paid when the visit is cancelled" do
    AssistantEval::Seeds.dentist_sep22_paid_60(@profile)
    dentist = days_of(Appointment, @profile).sole

    run_tool(:mark_done, @chat, type: "appointment", ref: "dentist", status: "cancelled")

    assert_equal "cancelled", dentist.reload.status
    assert_equal "completed", dentist.costs.sole.status
  end

  test "skipping a dose that was taken gives its supplies back" do
    AssistantEval::Seeds.b12_injection_series(@profile)
    event = doses.first.event
    dose = event.occurrence_on(Date.new(2026, 9, 24))
    needles = Supply.find_by!("lower(name) = 'needles'")
    event.replace_uses_for!(dose, [ [ needles.id, 1 ] ])
    dose.complete!
    stock = -> { SupplyPurchase.where(profile: @profile, supply: needles).sum(:quantity_remaining) }
    assert_equal 99, stock.call

    run_tool(:mark_done, @chat, type: "medication", ref: dose.id.to_s, status: "skipped")

    assert_equal "skipped", dose.reload.status
    assert_equal 100, stock.call
  end

  test "all doses this month at once, upcoming occurrences saved on the way" do
    AssistantEval::Seeds.b12_injection_series(@profile)

    result = run_tool(:mark_done, @chat, type: "medication", all: true, date_from: "2026-09-01", date_to: "2026-09-24")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ Date.new(2026, 9, 3), Date.new(2026, 9, 10), Date.new(2026, 9, 17), Date.new(2026, 9, 24) ],
                 doses.where(status: :completed).pluck(:date)
  end

  test "a status the type can't have is the model's mistake to fix" do
    AssistantEval::Seeds.b12_injection_series(@profile)

    result = run_tool(:mark_done, @chat, type: "medication", ref: "cobalamin today", status: "in_progress")

    assert_match "use one of", result.dig(:data, :changes, 0, :problems, 0).to_s + result[:error].to_s
  end

  test "dates it can't read, for many at once, are the model's mistake to fix" do
    AssistantEval::Seeds.b12_injection_series(@profile)

    result = run_tool(:mark_done, @chat, type: "medication", all: true, date_from: "sometime soon")

    assert_not result[:ok]
    assert_match "can't read the date", result[:error]
  end
end
