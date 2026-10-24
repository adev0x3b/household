# frozen_string_literal: true

require "test_helper"

# Where a notification leads, and what its row asks: the UI's side of it.
class Notifications::DestinationTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @recipe = recipes(:roast_chicken)
  end

  test "a shared thing can be opened; an unshared or deleted one can't" do
    shared = Notification.create!(profile: @bob, actor: @alice, kind: :shared, subject: @recipe)
    event = Notification.new(profile: @bob, kind: :shared, subject: events(:groceries))

    assert_equal routes.recipe_path(@recipe), destination(shared).path
    assert_equal routes.calendar_path(month: 3, year: 2026), destination(event).path
    assert_nil destination(Notification.new(profile: @bob, kind: :unshared, subject: @recipe)).path

    @recipe.destroy!
    assert_nil destination(shared.reload).path
  end

  test "a thing with no page of its own opens where it is seen" do
    shelf = Notification.new(profile: @bob, actor: @alice, kind: :shared, subject: @alice.bookshelf!)
    list = Notification.new(profile: @bob, actor: @alice, kind: :shared, subject: grocery_lists(:weekly_shop))
    language = Notification.new(profile: @alice, kind: :import_finished, subject: LexiconLanguage.find_by!(code: "it"))
    approval = Notification.new(profile: @alice, kind: :approval_declined, subject: LinkApproval.new)

    assert_equal routes.books_path(shelf: @alice.id), destination(shelf).path
    assert_equal routes.grocery_list_path(grocery_lists(:weekly_shop)), destination(list).path
    assert_equal routes.admin_lexicon_path("it"), destination(language).path
    assert_equal routes.links_path, destination(approval).path
  end

  test "a reminder opens its day, and the admin's news the console" do
    task = events(:groceries)
    reminder = Notification.new(profile: @bob, kind: :reminder_due, subject: task, data: { "date" => "2026-10-09" })
    deploy = Notification.new(profile: @alice, kind: :deploy_succeeded, data: { "destination" => "staging" })

    assert_equal routes.calendar_path(month: 10, year: 2026, anchor: "day_2026-10-09"), destination(reminder).path
    assert_nil destination(deploy).path, "not the admin"
    @alice.update!(role: :admin)
    assert_equal routes.admin_deployment_path, destination(deploy).path
  end

  test "the admin's alerts open the errors or the failed jobs, for the admin alone" do
    error = Notification.new(profile: @alice, kind: :error_reported, data: { "name" => "IOError" })
    job = Notification.new(profile: @alice, kind: :job_failed, data: { "name" => "Uploads::FinishJob" })

    assert_nil destination(error).path, "not the admin"
    @alice.update!(role: :admin)
    assert_equal routes.admin_errors_path, destination(error).path
    assert_equal "#{routes.admin_jobs_path}/failed/jobs", destination(job).path
  end

  test "a job's end opens what it was about" do
    import = LexiconImport.create!(language: "it", status: :failed, error: "no nouns found")
    failed = Notification.new(profile: @alice, kind: :import_failed, subject: import, data: { "language" => "Italian" })
    run = Notification.new(profile: @alice, kind: :eval_run_finished, data: { "run_id" => "20260926-120000-qwen3" })

    assert_equal routes.admin_lexicon_path("it", import: import.id), destination(failed).path
    assert_equal routes.assistant_evals_run_path("20260926-120000-qwen3"), destination(run).path
  end

  test "a password link made for the reader opens nothing" do
    assert_nil destination(Notification.new(profile: @bob, actor: @alice, kind: :password_link_made)).path
  end

  test "a request has its answers while it is open, for the one to give them" do
    link = Link.create!(requester: @alice, addressee: @bob)
    asked = Notification.new(profile: @bob, kind: :link_requested, subject: link)
    gone = Notification.new(profile: @bob, kind: :link_requested, subject_type: "Link", subject_id: 0)

    assert_empty destination(gone).actions

    assert_equal [ [ :accept, routes.link_acceptance_path(link), :post ], [ :decline, routes.link_path(link), :delete ] ], destination(asked).actions.map(&:deconstruct)
    assert_empty destination(Notification.new(profile: @alice, kind: :link_requested, subject: link)).actions, "not the asker's to answer"

    link.update!(status: :accepted, accepted_at: Time.current)
    assert_empty destination(asked).actions
  end

  private

  # The paths, asked of the routes rather than mixed into the test: mixed
  # in, a route named test_… (test_assistant_settings) became a test of its
  # own, which failed for want of a host whenever the routes were drawn
  # before the test ran.
  def routes = Rails.application.routes.url_helpers

  def destination(notification) = Notifications::Destination.new(notification)
end
