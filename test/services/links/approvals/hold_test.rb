# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# What a linked housemate's request is about: one dose of a series taken
# several times a day, so that two doses of one day are two requests.
class Links::Approvals::HoldTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    link!(@alice, @bob)
    grant(@alice, @bob, "Medication", write: :ask)
    @series = series!("Medication", profile: @alice, starts_on: Date.current, title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    @tomorrow = Date.current + 1
  end

  def ask(time) = Links::Approvals::Hold.call(requester: @bob, record: @series.occurrence_on(@tomorrow, time: time), kind: :complete)

  test "asking about the morning and the evening dose keeps two requests" do
    morning = ask("08:00")
    evening = ask("20:00")

    assert_equal [ "08:00", "20:00" ], [ morning, evening ].map(&:time_string)
    assert_equal 2, LinkApproval.pending.where(event: @series).count
  end

  test "asking again about the same dose refreshes its request" do
    first = ask("20:00")

    assert_equal first, ask("20:00")
    assert_equal 1, LinkApproval.pending.where(event: @series).count
  end

  test "a day without a time of day is asked about once" do
    task = series!("Task", profile: @alice, starts_on: Date.current, title: "Water the basil", rrule: "FREQ=DAILY")
    day = task.occurrence_on(@tomorrow)
    first = Links::Approvals::Hold.call(requester: @bob, record: day, kind: :complete)

    assert_nil first.time
    assert_equal first, Links::Approvals::Hold.call(requester: @bob, record: day, kind: :complete)
  end

  test "the database keeps one pending request per dose, untimed days included" do
    task = series!("Task", profile: @alice, starts_on: @tomorrow, title: "Water the basil")
    untimed = Links::Approvals::Hold.call(requester: @bob, record: task.occurrence_on(@tomorrow), kind: :complete)

    [ ask("20:00"), untimed ].each do |approval|
      assert_raises(ActiveRecord::RecordNotUnique) { approval.dup.save!(validate: false) }
    end
  end

  test "a request shows at once on the Links pages of the owner and the asker" do
    asker = nil
    owner = capture_turbo_stream_broadcasts([ @alice, :notifications ]) do
      asker = capture_turbo_stream_broadcasts([ @bob, :notifications ]) { ask("20:00") }
    end

    assert_includes owner.map { _1["target"] }, Views::Links::Sections::ID
    assert_includes asker.map { _1["target"] }, Views::Links::Sections::ID
  end

  test "a day whose name can't be read is asked about under its kind's name, and the failure is reported" do
    day = @series.occurrence_on(@tomorrow, time: "20:00")
    approval = nil

    report = assert_error_reported(RuntimeError) do
      swapping(day, :event_label, -> { raise "no name" }) do
        approval = Links::Approvals::Hold.call(requester: @bob, record: day, kind: :complete)
      end
    end

    assert report.handled, "the request is held all the same"
    assert_equal I18n.t("links.things.medication"), approval.title
  end
end
