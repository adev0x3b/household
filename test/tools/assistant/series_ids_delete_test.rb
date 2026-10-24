# frozen_string_literal: true

require "test_helper"

# A series' event_id as the ref of a deletion: the whole series goes when
# asked; one upcoming day with nothing saved can't be deleted, and the model
# is told what to do instead.
class Assistant::SeriesIdsDeleteTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    ActiveRecord::Base.connection.execute("SELECT setval('events_id_seq', nextval('events_id_seq') + 1000)")
    AssistantEval::Seeds.b12_injection_series(@profile)
    @series = Medication.where(profile: @profile).sole
  end

  teardown { travel_back }

  test "the whole series by its event_id waits for the button, then goes" do
    result = run_tool(:delete_records, @chat, type: "medication", ref: @series.id.to_s, whole_series: true)

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)
    assert_not Event.exists?(@series.id)
  end

  test "event_id as its own keyword works the same as ref" do
    result = run_tool(:delete_records, @chat, type: "medication", event_id: @series.id, whole_series: true)

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
  end

  test "one upcoming day with nothing saved says to skip it or delete the series" do
    result = run_tool(:delete_records, @chat, type: "medication", ref: @series.id.to_s)

    assert_match(/nothing saved: to stop the whole series use whole_series; to skip just that day use mark_done/, result.inspect)
    assert Event.exists?(@series.id)
  end

  test "all: true without whole_series only removes what's saved, and says so before the button" do
    result = run_tool(:delete_records, @chat, type: "medication", all: true, query: "cobalamin")

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    note = result[:data][:changes].sole[:notes].sole
    assert_match(/keeps repeating.*whole_series: true/, note)
    assert_match(/\ANOT SAVED YET\. #{Regexp.escape(note)}/, result[:data][:next])

    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)
    assert Event.exists?(@series.id), "the series itself is untouched"
    assert_not @series.occurrences.exists?(date: Date.new(2026, 9, 3)), "only the saved dose is gone"
    assert @series.reload.excluded_on?(Date.new(2026, 9, 3)), "and its day isn't projected again"
  end
end
