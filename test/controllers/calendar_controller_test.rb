# frozen_string_literal: true

require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = profiles(:alice)
    sign_in @profile
    @day = Date.new(2026, 10, 6)
  end

  test "every card's circle and the month and year pickers have a name" do
    task!(profile: @profile, date: @day, title: "Bins")
    expense!(profile: @profile, date: @day, cents: 2000, title: "Rent")

    get calendar_path(month: 10, year: 2026)

    assert_select "a.task-card__toggle[aria-label=?]", "Mark “Bins” done"
    assert_select "a.transaction-card__toggle[aria-label=?]", "Mark “Rent” not done"
    assert_select "a[class*='__toggle']:not([aria-label])", 0
    assert_select "#calendar_nav_month[aria-label=Month]"
    assert_select "#calendar_nav_year[aria-label=Year]"
  end

  test "an expense paid for an appointment shows inside its card, not as its own" do
    visit = appointment!(profile: @profile, date: @day, counterpart: "Moretti")
    fee = expense!(profile: @profile, date: @day, cents: 2000, status: :pending, about: visit, title: "Visit fee")

    get calendar_path(month: 10, year: 2026)

    assert_response :success
    assert_select ".transaction-card", count: 0
    assert_select ".appointment-card .attached-cost--pending" do
      assert_select ".attached-cost__amount", text: /20/
      assert_select "a.attached-cost__toggle[href=?][data-turbo-method=post]", event_day_completion_path(fee.event, fee.date)
    end
  end

  test "an expense paid for something on another day keeps its own card" do
    visit = appointment!(profile: @profile, date: @day)
    expense!(profile: @profile, date: @day + 1, cents: 2000, about: visit)
    expense!(profile: @profile, date: @day, cents: 500)

    get calendar_path(month: 10, year: 2026)

    assert_select ".transaction-card", count: 2
    assert_select ".attached-cost", count: 0
  end

  test "a fee entered with an appointment stays pending, like the appointment" do
    post appointments_path, as: :turbo_stream, params: {
      appointment: { title: "Dermatologist", date: @day.iso8601, details_attributes: { kind: "medical", counterpart: "Polo salute" } },
      transaction: { amount: "20", payment_method: "card" }
    }

    visit = Appointment.find_by!(title: "Dermatologist").first_occurrence
    assert_predicate visit, :pending?
    cost = visit.costs.sole
    assert_predicate cost, :pending?
    assert_nil cost.completed_at
    assert_equal "Appointment with Polo salute on #{I18n.l(@day, format: :long)}", cost.event.title
  end

  # Bob: Alice's fixtures take Metformin twice a day already.
  test "a medication taken twice a day is two cards on the day, in clock order, each its own dose" do
    bob = profiles(:bob)
    sign_in bob
    event = timed_medication!(profile: bob, starts_on: @day, times: %w[CV 08:00]).event
    event.occurrence_on(@day + 1, time: "19:30").complete!

    get calendar_path(month: 10, year: 2026)

    assert_response :success
    assert_select "#day_2026-10-07 .medication-card", count: 2
    assert_select "#day_2026-10-07 .medication-card:first-child .medication-card__time", text: /08:00/
    assert_select "#day_2026-10-07 .medication-card:last-child .medication-card__time", text: /with dinner/
    assert_select "#day_2026-10-07 .medication-card--completed", count: 1
    assert_select "#day_2026-10-07 a.medication-card__toggle--projected[href=?][data-turbo-method=post]",
                  event_day_completion_path(event, "2026-10-07", time: "08:00")
    assert_select "#day_2026-10-07 a.medication-card__name-link[href=?]",
                  edit_event_day_path(event, "2026-10-07", time: "08:00")
    assert_select "#day_2026-10-08 a.medication-card__name-link[href=?]",
                  edit_event_day_path(event, "2026-10-08", time: "19:30")
    assert_select "#day_2026-10-08 .medication-card__time", count: 2
  end

  test "a dose saved before the series got its times still shows on its day" do
    bob = profiles(:bob)
    sign_in bob
    untimed = medication!(profile: bob, date: @day)
    untimed.event.update!(event_slots: EventSlot.rows_for(%w[08:00 20:00]))

    get calendar_path(month: 10, year: 2026)

    assert_select "#day_2026-10-06 .medication-card", count: 3
    assert_select "#day_2026-10-06 .medication-card:last-child a.medication-card__name-link[href=?]", edit_event_day_path(untimed.event, untimed.date)
  end

  test "a week is a row: the days before the 1st and after the last are shown from the months beside, named by their month" do
    task!(profile: @profile, date: Date.new(2026, 9, 30), title: "Last of September")

    get calendar_path(month: 10, year: 2026)

    assert_select ".calendar__weekday", count: 7
    assert_select ".calendar__weekday:first-of-type", text: "Mon"
    assert_select ".day-card", count: 35
    assert_select "#day_2026-09-28.day-card--beside .day-card__day-name", text: "Sep"
    assert_select "#day_2026-09-30.day-card--beside .task-card__title-link", text: "Last of September"
    assert_select "#day_2026-11-01.day-card--beside .day-card__day-name", text: "Nov"
    assert_select "#day_2026-10-01:not(.day-card--beside) .day-card__day-name", text: "Thu"
    assert_select "#day_2026-09-28 .day-card__add-btn[data-day-add-date-param=?]", "2026-09-28"
  end

  test "a day with nothing on it says so" do
    get calendar_path(month: 1, year: 2000)

    assert_select "#day_2000-01-05 .day-card__empty", text: "Nothing planned"
    assert_select "#day_2000-01-05 .day-card__body", count: 0
  end

  test "each day's + names its day to the page's one menu of every kind, each in its section's colour" do
    get calendar_path(month: 10, year: 2026)

    assert_select "#day_2026-10-06 .day-card__add-btn[data-day-add-date-param=?]", "2026-10-06"
    assert_select ".day-card [role=menu]", 0
    assert_select "#day_add_menu", 1
    assert_select "#day_add_menu button.day-add-menu__option", count: Event::TYPES.size
    assert_select "#day_add_menu button.day-add-menu__option.section--agenda[formaction=?]", new_task_path
    assert_select "#day_add_menu button.day-add-menu__option.section--healthcare[formaction=?]", new_appointment_path
    assert_select "#day_add_menu button.day-add-menu__option.section--finance[formaction=?]", new_transaction_path
    assert_select "#day_add_menu button.day-add-menu__option.section--pantry[formaction=?]", new_meal_path
    assert_select "#card_menu", 1
  end

  test "an appointment takes its kind's section: a visit is Healthcare, an interview Agenda" do
    appointment!(profile: @profile, date: @day, kind: :medical, counterpart: "Dr. Moretti", title: "Checkup")
    appointment!(profile: @profile, date: @day, kind: :work, counterpart: "ACME", title: "Interview")

    get calendar_path(month: 10, year: 2026)

    assert_select "#day_2026-10-06 .appointment-card.section--healthcare", text: /Checkup/ do
      assert_select ".appointment-card__kind-icon.fa-user-doctor"
      assert_select ".appointment-card__detail", text: /Dr. Moretti/
    end
    assert_select "#day_2026-10-06 .appointment-card.section--agenda", text: /Interview/ do
      assert_select ".appointment-card__kind-icon.fa-briefcase"
      assert_select ".appointment-card__detail", text: /ACME/
    end
  end

  test "a projected day of a series opens its form and ticks in one step; a saved one by its own id" do
    task = task!(profile: @profile, date: @day, title: "Water the plants")
    task.event.update!(rrule: "FREQ=WEEKLY")

    get calendar_path(month: 10, year: 2026)

    assert_select "#day_2026-10-06 a.task-card__title-link[href=?]", edit_event_day_path(task.event, "2026-10-06")
    assert_select "#day_2026-10-06 a.task-card__toggle[href=?][data-turbo-method=post]", event_day_completion_path(task.event, "2026-10-06")
    assert_select "#day_2026-10-13 .task-card--projected a.task-card__title-link[href=?]", edit_event_day_path(task.event, "2026-10-13")
    assert_select "#day_2026-10-13 a.task-card__toggle--projected[href=?][data-turbo-method=post]", event_day_completion_path(task.event, "2026-10-13")
  end

  test "a done day's circle asks to reopen it, not to flip it" do
    task = task!(profile: @profile, date: @day, title: "Water the plants")
    task.complete!

    get calendar_path(month: 10, year: 2026)

    assert_select "#day_2026-10-06 a.task-card__toggle--completed[href=?][data-turbo-method=delete]", event_day_completion_path(task.event, "2026-10-06")
  end

  test "a payment to a housemate is an income on their calendar, read-only" do
    housemate = profiles(:bob)
    transfer!(payer: @profile, counterparty: housemate, date: @day, cents: 1500)

    get calendar_path(month: 10, year: 2026)
    assert_select "#day_2026-10-06 .transaction-card--expense"
    assert_select "#day_2026-10-06 .transaction-card__kind", count: 0
    assert_select "#day_2026-10-06 .transaction-card__amount", text: /-.*15/

    sign_out :profile
    sign_in housemate
    get calendar_path(month: 10, year: 2026)

    assert_select "#day_2026-10-06 .transaction-card--income" do
      assert_select ".transaction-card__kind", text: "Income"
      assert_select ".transaction-card__amount", text: /\+.*15/
      assert_select ".transaction-card__toggle.is-locked"
      assert_select ".item-menu__button", 0
    end
  end
end
