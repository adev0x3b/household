# frozen_string_literal: true

require "test_helper"

# A series keeps the first day a scheduled day of it may have nothing saved
# about (Event#unsaved_since), so "needs attention" reads from there rather
# than from the series' first day. Every scheduled day before it has a row,
# whoever wrote it and however; these walk the writers that can break that.
class Events::UnsavedFromTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 9, 12)
    @today = Date.current
    @doses = series!("Medication", profile: profiles(:carol), starts_on: @today - 4, title: "Metformin", slots: %w[08:00 20:00],
                                   rrule: Events::RecurrenceRule.build(frequency: "daily"))
  end

  def unsaved_since = @doses.reload.unsaved_since

  def save_every_dose(from, to)
    (from..to).each { |date| %w[08:00 20:00].each { |time| day!(@doses, date: date, time: time, status: :completed) } }
  end

  test "a series nothing was saved about reads from its first day" do
    assert_nil @doses.unsaved_from
    assert_equal @today - 4, unsaved_since
  end

  test "saving the slot at the mark moves it to the next slot without a row, and past today when every one has one" do
    day!(@doses, date: @today - 4, time: "08:00", status: :completed)
    assert_equal @today - 4, unsaved_since, "its evening dose has no row yet"

    day!(@doses, date: @today - 4, time: "20:00", status: :skipped)
    assert_equal @today - 3, unsaved_since

    save_every_dose(@today - 3, @today)
    assert_equal @today + 1, unsaved_since
  end

  test "a gap stays the mark, whatever is saved after it; a day ahead moves nothing" do
    day!(@doses, date: @today - 4, time: "08:00", status: :completed)
    day!(@doses, date: @today - 4, time: "20:00", status: :completed)
    save_every_dose(@today - 2, @today)
    assert_equal @today - 3, unsaved_since

    day!(@doses, date: @today + 3, time: "08:00", status: :pending)
    assert_equal @today - 3, unsaved_since
  end

  test "undoing a dose keeps its row, and moving the mark never touches the series' updated_at" do
    stamp = @doses.updated_at
    travel 1.minute do
      save_every_dose(@today - 4, @today)
      @doses.occurrence_on(@today - 4, time: "08:00").uncomplete!
    end

    assert_equal @today + 1, unsaved_since
    assert_equal stamp, @doses.reload.updated_at
  end

  test "a day that goes or moves away takes the mark back to where it was" do
    save_every_dose(@today - 4, @today)

    @doses.occurrence_on(@today - 1, time: "20:00").destroy!
    assert_equal @today - 1, unsaved_since

    save_every_dose(@today - 1, @today - 1)
    @doses.occurrence_on(@today - 3, time: "08:00").update!(date: @today + 2)
    assert_equal @today - 3, unsaved_since
  end

  test "days deleted in bulk take each series back to the first of them" do
    save_every_dose(@today - 4, @today)
    chores = weekly_event(profile: profiles(:carol), type: Task, starts_on: @today - 14, title: "Bins")
    [ @today - 14, @today - 7 ].each { |date| day!(chores, date: date, status: :completed) }

    Occurrence.delete_with_children(Occurrence.where(event: @doses, date: (@today - 2)..).or(Occurrence.where(event: chores)))

    assert_equal @today - 2, unsaved_since
    assert_equal @today - 14, chores.reload.unsaved_since
  end

  test "a day deleted from the calendar takes the mark back, and stays off the schedule" do
    save_every_dose(@today - 4, @today)

    Occurrences::Destroy.call(@doses.occurrence_on(@today - 2, time: "08:00"), by: profiles(:carol))

    assert_equal @today - 2, unsaved_since
    assert_empty Reports::Unfinished.new(audience_for(profiles(:carol)), today: @today).entries
  end

  test "a day skipped and restored takes the mark back to it" do
    save_every_dose(@today - 4, @today)
    @doses.occurrence_on(@today - 2, time: "08:00").destroy!
    @doses.skip!(@today - 2, time: "08:00")
    day!(@doses, date: @today - 2, time: "20:00", status: :completed)

    @doses.unskip!(@today - 2, time: "08:00")

    assert_equal @today - 2, unsaved_since
  end

  test "a new rule, start or set of times finds the mark again from the series' start" do
    save_every_dose(@today - 4, @today)

    @doses.assign_slots(%w[08:00 14:00 20:00])
    assert_equal @today - 4, unsaved_since, "the new afternoon dose has no row on the days passed"

    @doses.assign_slots(%w[08:00 20:00])
    assert_equal @today + 1, unsaved_since

    @doses.update!(starts_on: @today - 6)
    assert_equal @today - 6, unsaved_since

    @doses.update!(rrule: Events::RecurrenceRule.build(frequency: "daily", interval: 2))
    assert_equal @today - 6, unsaved_since
    @doses.update!(starts_on: @today - 4)
    assert_equal @today + 1, unsaved_since
  end

  test "what needs attention is the same wherever the mark is, from the series' first day to its first gap" do
    save_every_dose(@today - 4, @today - 3)
    day!(@doses, date: @today - 1, time: "08:00", status: :pending)
    expected = Reports::Unfinished.new(audience_for(profiles(:carol)), today: @today).entries.map { [ _1.date, _1.time ] }
    assert_equal [ [ @today - 2, "08:00" ], [ @today - 2, "20:00" ], [ @today - 1, "08:00" ], [ @today - 1, "20:00" ] ], expected

    [ nil, @today - 4, @today - 3, @today - 2 ].each do |mark|
      @doses.update_column(:unsaved_from, mark)
      assert_equal expected, Reports::Unfinished.new(audience_for(profiles(:carol)), today: @today).entries.map { [ _1.date, _1.time ] }, mark.to_s
    end
  end
end
