# frozen_string_literal: true

require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    sign_in @alice
    @task = occurrences(:groceries_due) # Alice's "Buy groceries", 2026-03-02
  end

  def fields(**overrides)
    { title: @task.title, notes: @task.notes, details_attributes: { priority: @task.details.priority } }.merge(overrides)
  end

  test "a new task keeps the reminders its form was given, for whoever saved it" do
    post tasks_path, as: :turbo_stream, params: {
      task: { title: "Pay the rent", date: "2026-11-01", details_attributes: { priority: "high" } },
      event: { frequency: "none", reminders_submitted: "1", reminders: { "-1" => { amount: "2", unit: "days" }, "-2" => { amount: "3", unit: "hours" } } }
    }

    assert_response :success
    event = Task.find_by!(title: "Pay the rent")
    assert_equal Date.new(2026, 11, 1), event.starts_on
    assert_equal "high", event.details.priority
    assert_equal [ [ @alice.id, 180 ], [ @alice.id, 2880 ] ], event.event_reminders.order(:offset_minutes).pluck(:profile_id, :offset_minutes)
  end

  test "the form of a new task posts under task[...] for that day" do
    get new_task_path(date: "2026-11-01"), as: :turbo_stream

    assert_response :success
    assert_select "form[action=?][method=post]", tasks_path
    assert_select "input[name='task[title]']"
    assert_select "input[type=hidden][name='task[date]'][value='2026-11-01']"
    assert_select "select[name='task[details_attributes][priority]']"
    assert_select "select[name='task[status]']", 0
    assert_select "select[name='task[apply_to]']", 0
  end

  test "editing shows only your own reminders, and saving them leaves the others' alone" do
    event = @task.event
    event.event_reminders.create!(profile: @alice, offset_minutes: 120)
    event.event_reminders.create!(profile: @bob, offset_minutes: 1440)

    get edit_event_day_path(event, @task.date), as: :turbo_stream
    assert_select "form[action=?]", event_day_path(event, @task.date)
    assert_select "input[name='task[title]'][value='Buy groceries']"
    assert_select "select[name='task[status]']"
    assert_select "input[name='event[reminders][0][amount]'][value='2']"
    assert_select "select[name='event[reminders][0][unit]'] option[selected][value='hours']"
    assert_select ".reminder-fields__row", 1 + 1 # one of Alice's, and the blank template's

    patch event_day_path(event, @task.date), as: :turbo_stream, params: { task: fields, event: { frequency: "none", reminders_submitted: "1" } }

    assert_equal [ @bob.id ], event.event_reminders.reload.pluck(:profile_id)
  end

  test "a reminder may come by email too once mail can reach the person; until their address is confirmed, the form says where to confirm it" do
    @task.event.event_reminders.create!(profile: @alice, offset_minutes: 120, by_email: true)

    get edit_event_day_path(@task.event, @task.date), as: :turbo_stream
    assert_select "input[name='event[reminders][0][by_email]']", count: 0
    assert_select ".reminder-fields a[href=?]", account_path, count: 0

    with_relay { get edit_event_day_path(@task.event, @task.date), as: :turbo_stream }
    assert_select "input[name='event[reminders][0][by_email]']", count: 0
    assert_select ".reminder-fields .help a[href=?]", account_path, text: "Confirm it on your account page."

    @alice.update!(email_confirmed_at: 1.day.ago)
    with_relay { get edit_event_day_path(@task.event, @task.date), as: :turbo_stream }
    assert_select "input[type=hidden][name='event[reminders][0][by_email]'][value='0'] + label input[type=checkbox][value='1'][checked]"
    assert_select "template input[type=checkbox][name$='[by_email]']:not([checked])"

    reminders = { "0" => { amount: "2", unit: "hours", by_email: "0" }, "-1" => { amount: "1", unit: "days", by_email: "1" } }
    patch event_day_path(@task.event, @task.date), as: :turbo_stream, params: { task: fields, event: { frequency: "none", reminders_submitted: "1", reminders: reminders } }
    assert_equal [ [ 120, false ], [ 1440, true ] ], @task.event.event_reminders.order(:offset_minutes).pluck(:offset_minutes, :by_email)
  end

  test "a save without the reminder rows leaves reminders as they are" do
    @task.event.event_reminders.create!(profile: @alice, offset_minutes: 120)

    patch event_day_path(@task.event, @task.date), as: :turbo_stream, params: { task: fields(title: "Renamed"), event: { frequency: "none" } }

    assert_equal "Renamed", @task.reload.title
    assert_equal "Renamed", @task.event.reload.title, "a one-off's day is its series"
    assert_equal 1, @task.event.event_reminders.count
  end

  test "a day of a recurring series changes alone, unless the whole series is chosen" do
    day = occurrences(:groceries_due)
    day.event.update!(rrule: "FREQ=WEEKLY")

    get edit_event_day_path(day.event, day.date), as: :turbo_stream
    assert_select "select[name='task[apply_to]'] option[selected][value=day]"
    assert_select "select[name='task[apply_to]'] option[value=series]"
    fields = css_select(".modal__body select, .modal__body input:not([type=hidden]), .modal__body textarea").map { _1["name"] }
    assert_equal "task[apply_to]", fields.first, "what Save changes is chosen before the fields it governs"

    patch event_day_path(day.event, day.date), as: :turbo_stream, params: { task: fields(title: "Groceries and milk", apply_to: "day"), event: { frequency: "weekly", interval: 1 } }
    assert_equal "Groceries and milk", day.reload.title
    assert_equal "Buy groceries", day.event.reload.title

    patch event_day_path(day.event, day.date), as: :turbo_stream, params: { task: fields(title: "Weekly shop", apply_to: "series", details_attributes: { priority: "urgent" }),
                                                                            event: { frequency: "weekly", interval: 1 } }
    assert_equal "Weekly shop", day.event.reload.title
    assert_equal "urgent", day.event.details.priority
  end
end
