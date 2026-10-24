# frozen_string_literal: true

require "test_helper"

# A linked housemate acting on someone's items through the calendar: what
# their grants let them do outright, what waits for the owner's OK, and
# what stays out of reach.
class LinkedItemsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @task = occurrences(:groceries_due) # Alice's "Buy groceries", on 2026-03-02
    link!(@alice, @bob)
    sign_in @bob
  end

  def task_params(**fields)
    { task: { title: @task.title, notes: @task.notes, status: @task.status, details_attributes: { priority: @task.details.priority } }.merge(fields),
      event: { frequency: "none" } }
  end

  test "the partner's items are on the calendar, marked as theirs" do
    get calendar_path(month: 3, year: 2026)

    assert_select "#day_2026-03-02 .task-card .card-actions__owner", text: "Alice"
    assert_select "#day_2026-03-02 .task-card a.item-action[href*=\"/shares/new\"]", 0
  end

  test "what the partner may only see opens read-only and can't be ticked" do
    grant(@alice, @bob, "Task", write: :off, delete: :off)

    get calendar_path(month: 3, year: 2026)
    assert_select "#day_2026-03-02 .task-card .task-card__toggle.is-locked"
    assert_select "#day_2026-03-02 .task-card", text: /Buy groceries/ do
      assert_select ".item-menu__button", 0, "nothing to change the status of, nothing to delete"
    end

    get edit_event_day_path(@task.event, @task.date), as: :turbo_stream
    assert_response :success
    assert_select "fieldset.modal__readonly[disabled]"
    assert_select "input[type=submit]", 0

    patch event_day_path(@task.event, @task.date), params: task_params(title: "Hacked"), as: :turbo_stream
    assert_equal "Buy groceries", @task.reload.title
  end

  test "a change the owner must OK is held, and applied when they approve" do
    get edit_event_day_path(@task.event, @task.date), as: :turbo_stream
    assert_select ".notice--action", text: /Alice will be asked/
    assert_select "input[type=submit][value='Ask Alice']"

    assert_difference "LinkApproval.count", 1 do
      patch event_day_path(@task.event, @task.date), params: task_params(title: "Buy groceries and milk"), as: :turbo_stream
    end
    assert_equal "Buy groceries", @task.reload.title

    approval = LinkApproval.last
    assert_equal [ @bob, @alice, "update", "pending" ], [ approval.requester, approval.owner, approval.action_kind, approval.status ]
    assert_equal({ "task" => { "title" => "Buy groceries and milk" } }, approval.payload)
    notification = @alice.notifications.approval_requested.last
    assert_equal "Bob asks to change your task", wording_of(notification).title
    assert_equal [ :approve, :decline ], Notifications::Destination.new(notification).actions.map(&:name)

    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream

    assert_equal "Buy groceries and milk", @task.reload.title
    assert_predicate approval.reload, :approved?
    assert_equal "Alice approved your change to their task", wording_of(@bob.notifications.last).title
    assert_empty Notifications::Destination.new(notification.reload).actions
  end

  test "a change with an error isn't asked for: its form comes back saying what is wrong" do
    assert_no_difference "LinkApproval.count" do
      patch event_day_path(@task.event, @task.date), params: task_params(title: ""), as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_select "form[action=?]", event_day_path(@task.event, @task.date)
    assert_includes response.body, "Title can&#39;t be blank"
  end

  test "asking again about the same day refreshes the request" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: "One"), as: :turbo_stream
    assert_no_difference "LinkApproval.count" do
      patch event_day_path(@task.event, @task.date), params: task_params(title: "Two"), as: :turbo_stream
    end
    assert_equal "Two", LinkApproval.last.payload.dig("task", "title")
  end

  test "declined is left as it was" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: "Nope"), as: :turbo_stream
    approval = LinkApproval.last

    sign_out :profile
    sign_in @alice
    delete link_approval_path(approval), as: :turbo_stream

    assert_predicate approval.reload, :declined?
    assert_equal "Buy groceries", @task.reload.title
    assert_equal "Alice declined your change to their task", wording_of(@bob.notifications.last).title
  end

  test "only the owner answers, and only once" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: "Mine now"), as: :turbo_stream
    approval = LinkApproval.last

    post link_approval_consent_path(approval), as: :turbo_stream
    assert_predicate approval.reload, :pending?

    sign_out :profile
    sign_in @alice
    delete link_approval_path(approval), as: :turbo_stream
    post link_approval_consent_path(approval), as: :turbo_stream
    assert_response :unprocessable_content
    assert_toast I18n.t("links.notices.decided")
    assert_predicate approval.reload, :declined?
    assert_equal "Buy groceries", @task.reload.title
  end

  test "the asker can take it back" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: "Maybe"), as: :turbo_stream
    approval = LinkApproval.last

    delete link_approval_path(approval), as: :turbo_stream
    assert_predicate approval.reload, :withdrawn?
  end

  test "with write on the change is saved at once" do
    grant(@alice, @bob, "Task", write: :on)

    assert_no_difference "LinkApproval.count" do
      patch event_day_path(@task.event, @task.date), params: task_params(title: "Straight in"), as: :turbo_stream
    end
    assert_equal "Straight in", @task.reload.title
  end

  test "ticking is a change too" do
    post event_day_completion_path(@task.event, @task.date), as: :turbo_stream
    assert_predicate @task.reload, :pending?
    assert_equal "complete", LinkApproval.last.action_kind

    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(LinkApproval.last), as: :turbo_stream
    assert_predicate @task.reload, :completed?
  end

  test "a new item on the partner's calendar, asked for and then added as theirs" do
    get new_task_path(date: "2026-11-02"), as: :turbo_stream
    assert_select "select[name=owner_id] option", 2

    assert_no_difference "Task.count" do
      post tasks_path, params: { owner_id: @alice.id, task: { title: "Fix the shelf", date: "2026-11-02", details_attributes: { priority: "low" } },
                                 event: { frequency: "none" } }, as: :turbo_stream
    end
    approval = LinkApproval.last
    assert_equal "create", approval.action_kind
    assert_nil approval.event

    sign_out :profile
    sign_in @alice
    assert_difference "Task.count", 1 do
      post link_approval_consent_path(approval), as: :turbo_stream
    end
    assert_equal @alice, Task.find_by!(title: "Fix the shelf").profile
  end

  test "adding is refused on the calendar of someone who doesn't allow it" do
    grant(@alice, @bob, "Task", create: :off)

    assert_no_difference [ "Task.count", "LinkApproval.count" ] do
      post tasks_path, params: { owner_id: @alice.id, task: { title: "Nope", date: "2026-11-02", details_attributes: { priority: "low" } },
                                 event: { frequency: "none" } }, as: :turbo_stream
    end
    assert_no_difference [ "Task.count", "LinkApproval.count" ] do
      post tasks_path, params: { owner_id: profiles(:carol).id, task: { title: "Nope", date: "2026-11-02", details_attributes: { priority: "low" } },
                                 event: { frequency: "none" } }, as: :turbo_stream
    end
  end

  test "deleting a day: on, asked, refused" do
    event = @task.event

    delete event_day_path(event, "2026-03-02"), as: :turbo_stream
    assert Occurrence.exists?(@task.id), "asked first"
    approval = LinkApproval.last
    assert_equal [ "destroy", "occurrence", @task.id ], [ approval.action_kind, approval.scope, approval.occurrence_id ]

    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream
    assert_not Occurrence.exists?(@task.id)

    grant(@alice, @bob, "Task", delete: :off)
    other = Occurrences::Create.call(Task.new(title: "Water plants", starts_on: Date.new(2026, 3, 5), details_attributes: { priority: :low }), by: @alice)
    sign_out :profile
    sign_in @bob
    assert_no_difference "LinkApproval.count" do
      delete event_day_path(other, "2026-03-05"), as: :turbo_stream
    end
    assert Task.exists?(other.id)
  end

  test "deleting a repeating series: asked as a whole, and approved as a whole" do
    plants = series!("Task", profile: @alice, starts_on: Date.new(2026, 3, 2), title: "Water the plants", rrule: "FREQ=WEEKLY", priority: :low)

    delete event_day_path(plants, "2026-03-09", scope: "series"), as: :turbo_stream
    assert Task.exists?(plants.id), "asked first"
    approval = LinkApproval.last
    assert_equal [ "destroy", "series" ], [ approval.action_kind, approval.scope ]

    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream
    assert_not Task.exists?(plants.id), "every day of it, not the one it was asked from"
  end

  test "a medication taken twice a day: each request is about the dose it was made on" do
    metformin = series!("Medication", profile: @alice, starts_on: Date.new(2026, 3, 2), title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    doses = -> { metformin.reload.occurrences_between(Date.new(2026, 3, 3), Date.new(2026, 3, 3)).map { [ _1.time_string, _1.status ] } }

    post event_day_completion_path(metformin, "2026-03-03", time: "20:00"), as: :turbo_stream
    approve_as_alice(LinkApproval.last)
    assert_equal [ [ "08:00", "pending" ], [ "20:00", "completed" ] ], doses.call

    delete event_day_completion_path(metformin, "2026-03-03", time: "20:00"), as: :turbo_stream
    approve_as_alice(LinkApproval.last)
    assert_equal [ [ "08:00", "pending" ], [ "20:00", "pending" ] ], doses.call

    delete event_day_path(metformin, "2026-03-03", time: "08:00"), as: :turbo_stream
    approve_as_alice(LinkApproval.last)
    assert_equal [ [ "20:00", "pending" ] ], doses.call
  end

  test "the owner deletes from the card without asking" do
    sign_out :profile
    sign_in @alice

    get calendar_path(month: 3, year: 2026)
    assert_select "#day_2026-03-02 .task-card .item-menu__button[data-card-menu-delete-url-param=?]:not([data-card-menu-delete-owner-param])",
                  event_day_path(@task.event, "2026-03-02")

    delete event_day_path(@task.event, "2026-03-02"), params: { scope: "occurrence" }, as: :turbo_stream
    assert_not Occurrence.exists?(@task.id)
  end

  test "a request about a series that is deleted is dropped" do
    delete event_day_path(@task.event, "2026-03-02"), as: :turbo_stream
    approval = LinkApproval.last
    Occurrences::Destroy.call(@task, by: @alice, scope: "series")

    assert_predicate approval.reload, :cancelled?
    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream
    assert_predicate approval.reload, :cancelled?
  end

  test "the owner's bell stops offering to approve a request about a series once it is gone" do
    delete event_day_path(@task.event, "2026-03-02"), as: :turbo_stream
    approval = LinkApproval.last
    notification = @alice.notifications.approval_requested.find_by!(subject: approval)
    assert_equal [ :approve, :decline ], Notifications::Destination.new(notification).actions.map(&:name)

    streams = capture_turbo_stream_broadcasts([ @alice, :notifications ]) do
      Occurrences::Destroy.call(@task, by: @alice, scope: "series")
    end

    row = streams.find { _1["action"] == "replace" && _1["target"] == "notification_#{notification.id}" }
    assert row, "the request's row is redrawn where it is open"
    assert_empty row.css("form[action='#{link_approval_consent_path(approval)}']")
  end

  test "an approval that can no longer be done fails and says why" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: ""), as: :turbo_stream
    assert_equal 0, LinkApproval.count, "invalid fields are refused before asking"

    patch event_day_path(@task.event, @task.date), params: task_params(title: "Fine"), as: :turbo_stream
    approval = LinkApproval.last
    approval.update!(occurrence_id: nil, date: Date.new(2026, 3, 3))

    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream

    assert_predicate approval.reload, :failed?
    assert_predicate approval, :failure_gone?
    assert_includes response.body, "It couldn&#39;t be done. It isn&#39;t there anymore."
    assert_equal "Buy groceries", @task.reload.title
  end

  test "the owner reads what would change in words: the kind's own fields too" do
    patch event_day_path(@task.event, @task.date), params: task_params(details_attributes: { priority: "high" }), as: :turbo_stream
    approval = LinkApproval.last
    assert_equal({ "task" => { "details_attributes" => { "priority" => "high" } } }, approval.payload)

    sign_out :profile
    sign_in @alice
    get links_path
    assert_select ".links__section--approvals .links__approval" do
      assert_select ".links__change-field", text: "Priority"
      assert_select "del", text: "Low"
      assert_select "ins", text: "High"
    end

    post link_approval_consent_path(approval), as: :turbo_stream
    assert_equal "high", @task.reload.details.priority
  end

  test "unlinking drops what waits" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: "Later"), as: :turbo_stream

    delete link_path(Link.between(@alice, @bob)), as: :turbo_stream
    assert_equal 0, LinkApproval.count
  end

  test "the Links page lists the asker's requests and the owner's approvals" do
    patch event_day_path(@task.event, @task.date), params: task_params(title: "Listed"), as: :turbo_stream

    get links_path
    assert_select ".links__section--asked .links__approval", 1
    assert_select ".links__section--asked a[data-turbo-method=delete]"

    sign_out :profile
    sign_in @alice
    get links_path
    assert_select ".links__section--approvals .links__approval ins", text: "Listed"
    assert_select "a.navbar-link[href='#{links_path}'] .links-badge [aria-hidden]", text: "1"
  end

  private

  # Alice answers yes to Bob's request, and Bob is signed in again.
  def approve_as_alice(approval)
    assert_predicate approval, :pending?
    sign_out :profile
    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream
    assert_predicate approval.reload, :approved?
    sign_out :profile
    sign_in @bob
  end
end
