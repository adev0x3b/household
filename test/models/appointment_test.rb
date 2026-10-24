# frozen_string_literal: true

require "test_helper"

class AppointmentTest < ActiveSupport::TestCase
  test "requires a title" do
    appointment = Appointment.new(profile: profiles(:alice), starts_on: Date.current)
    assert_not appointment.valid?
    assert_includes appointment.errors[:title], "can't be blank"
  end

  test "is medical unless said, and its kind decides section and fee category" do
    visit = events(:endocrinologist)
    assert_predicate visit.kind, :medical?
    assert_equal :healthcare, visit.section
    assert_equal :healthcare, visit.fee_category
    assert_equal "Dr. Smith", visit.counterpart

    interview = Appointment.create!(profile: profiles(:alice), starts_on: Date.current, title: "Interview", details_attributes: { kind: :work, counterpart: "ACME" })
    assert_equal :agenda, interview.section
    assert_equal :miscellaneous, interview.fee_category
    assert_equal :entertainment, Appointment::Kind.new("social").fee_category
  end

  test "the kind's word for who it is with" do
    assert_equal "appointments.form.counterpart.medical", Appointment::Kind.new("medical").counterpart_label_key
    assert_equal "Provider", I18n.t("appointments.form.counterpart.medical.label")
    assert_equal "With", I18n.t("appointments.form.counterpart.work.label")
    assert_raises(ArgumentError) { Appointment::Kind.new("bogus") }
    assert_equal %w[medical], Appointment::Kind.for_section(:healthcare)
    assert_equal %w[work social personal other], Appointment::Kind.for_section(:agenda)
  end

  test "is due at its start time, or in the morning" do
    visit = events(:endocrinologist)
    day = visit.occurrence_on(Date.new(2026, 3, 16))
    assert_equal [ [ 9, 0 ], false ], visit.due_clock(day)

    visit.update!(start_time: "14:30")
    assert_equal [ [ 14, 30 ], true ], visit.due_clock(day)
    day.start_time = "16:00"
    assert_equal [ [ 16, 0 ], true ], visit.due_clock(day), "a day's own time wins"
  end

  test "the fee's title names who it was with, and the fee is paid to them" do
    assert_equal "Appointment with Dr. Smith on March 2, 2026", events(:endocrinologist).cost_title(occurrences(:endocrinologist_due))
    assert_equal "Dr. Smith", events(:endocrinologist).cost_counterpart(occurrences(:endocrinologist_due))
  end

  test "a kind with no one to pay by default leaves the counterpart to the cost" do
    task = Task.new(profile: profiles(:alice), title: "Taxes", starts_on: Date.current)

    assert_nil task.cost_counterpart(task.first_occurrence)
    assert_equal "Taxes", task.cost_title(task.first_occurrence)
  end

  test "an appointment sorts among a day's cards at the neutral priority" do
    assert_equal Event::DEFAULT_PRIORITY_RANK, events(:endocrinologist).priority_rank
  end
end
