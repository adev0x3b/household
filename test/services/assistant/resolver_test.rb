# frozen_string_literal: true

require "test_helper"

# The record an operation's `ref` means (Assistant::ChangeSets::Resolver):
# a handle, an id, a series on a day, one dose of a day — or why not.
class Assistant::ResolverTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 7, 12) # a Wednesday
    @alice = profiles(:alice)
    @bins = weekly_event(profile: @alice, type: "Task", starts_on: Date.new(2026, 10, 5), title: "Bins") # Mondays
  end

  teardown { travel_back }

  def resolve(type, ref, profile: @alice, **options) = Assistant::ChangeSets::Resolver.new(profile).resolve(type, ref, **options)

  test "a handle is a record made earlier in the same change" do
    resolution = resolve("task", "$repot")
    assert_equal "$repot", resolution.handle
    assert_predicate resolution, :resolved?
  end

  test "a series names its day: given, today's, or with upcoming its next one; a day off its schedule or a series not there is said" do
    monday = resolve("task", "event_id #{@bins.id} on 2026-10-12").record
    assert_equal [ @bins, Date.new(2026, 10, 12) ], [ monday.event, monday.date ]

    assert_match "has nothing on 2026-10-07 — say which day", resolve("task", "event_id #{@bins.id}").problem, "nothing today"
    assert_equal Date.new(2026, 10, 12), resolve("task", "event_id #{@bins.id}", upcoming: true).record.date, "its next one"
    assert_match "has nothing on 2026-10-08", resolve("task", "event_id #{@bins.id} on 2026-10-08").problem
    assert_match "no task or series with id 0", resolve("task", "event_id 0 on 2026-10-12").problem

    saved = day!(@bins, date: Date.new(2026, 10, 5))
    assert_equal saved, resolve("task", "#{saved.id} on 2026-10-05").record, "a day's own id on its date"
  end

  test "a day saved off its schedule is found on its day; which dose by the time it was taken" do
    moved = @bins.occurrence_on(Date.new(2026, 10, 5)).tap { _1.update!(date: Date.new(2026, 10, 6)) }
    assert_equal moved, resolve("task", "event_id #{@bins.id} on 2026-10-06").record

    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    evening = resolve("medication", "event_id #{twice.id} on 2026-10-07 at 20:00").record
    assert_equal "20:00", evening.time_string
  end

  test "nothing of that kind lately is said, to ask which one" do
    assert_match "no recent task found — say which one", resolve("task", nil, profile: AssistantEval::Sandbox.profile!).problem
  end

  test "the latest purchase when none is named; a kind without series, or a day not read, never by its series" do
    supply_purchase!(profile: @alice, name: "Needles", purchased_on: Date.current - 40)
    swabs = supply_purchase!(profile: @alice, name: "Swabs", purchased_on: Date.current - 2)
    latest = resolve("supply_purchase", nil)
    assert_equal swabs, latest.record
    assert latest.assumed

    assert_match "no supply_purchase or series with id #{swabs.id}", resolve("supply_purchase", "event_id #{swabs.id} on today").problem
    assert_nil resolve("task", "event_id #{@bins.id} on someday soon").record
  end

  test "a dose saved at one time, asked at another, is that other dose of its day" do
    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    morning = day!(twice, date: Date.new(2026, 10, 7), time: "08:00")
    evening = Assistant::ChangeSets::Resolver.new(@alice).resolve("medication", "#{morning.id} at 20:00").record
    assert_equal [ Date.new(2026, 10, 7), "20:00" ], [ evening.date, evening.time_string ]
  end

  test "in a chat, what it just saved is what \"it\" means" do
    chat = assistant_chat(@alice)
    data = Assistant::ChangeSets::Submit.call(chat: chat, operations: [ { op: "create", type: "task", fields: { title: "Call the vet", date: "today" } } ], confirm: true)
    assert_equal "saved", data[:status].to_s, data.inspect
    resolution = Assistant::ChangeSets::Resolver.new(@alice, chat: chat).resolve("task", nil)
    assert_equal "Call the vet", resolution.record.event.title
    assert_not resolution.assumed, "the chat's own, not a guess"
  end
end
