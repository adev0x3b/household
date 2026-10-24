# frozen_string_literal: true

require "test_helper"

class Reminders::DueAtTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 9)
    @rome = ActiveSupport::TimeZone["Europe/Rome"]
    @alice = profiles(:alice)
  end

  test "an appointment is due at its start time, on the person's clock" do
    visit = Appointment.new(profile: @alice, starts_on: @date, title: "Visit", start_time: "14:30")

    assert_equal [ @rome.local(2026, 10, 9, 14, 30), true ], Reminders::DueAt.for(visit.occurrence_on(@date), @rome)
  end

  test "a meal at its usual hour, anything without a time in the morning" do
    dinner = Meal.new(profile: @alice, starts_on: @date, title: "Out", details_attributes: { kind: :eating_out, meal_type: :dinner })
    assert_equal [ @rome.local(2026, 10, 9, 19, 30), false ], Reminders::DueAt.for(dinner.occurrence_on(@date), @rome)
    assert_equal [ @rome.local(2026, 10, 9, 9, 0), false ], Reminders::DueAt.for(Task.new(profile: @alice, starts_on: @date).occurrence_on(@date), @rome)
    assert_equal [ @rome.local(2026, 10, 9, 9, 0), false ], Reminders::DueAt.for(Appointment.new(profile: @alice, starts_on: @date).occurrence_on(@date), @rome)
  end

  test "a dose at its slot, else in the morning" do
    pill = Medication.new(profile: @alice, starts_on: @date, title: "Pill", details_attributes: { kind: :pill })
    assert_equal [ @rome.local(2026, 10, 9, 20, 0), true ], Reminders::DueAt.for(pill.occurrence_on(@date, time: "20:00"), @rome)
    assert_equal [ @rome.local(2026, 10, 9, 9, 0), false ], Reminders::DueAt.for(pill.occurrence_on(@date), @rome)
    assert_equal [ @rome.local(2026, 10, 9, 8, 0), true ], Reminders::DueAt.for(pill.occurrence_on(@date, time: "CM"), @rome)
  end
end
