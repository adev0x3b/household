# frozen_string_literal: true

require "test_helper"

# /admin/errors (Solid Errors) and /admin/jobs (Mission Control – Jobs): the
# admin's, behind their sign-in. Anyone else signed in finds nothing.
class Admin::EnginesTest < ActionDispatch::IntegrationTest
  setup do
    # The errors' tables, in this test's transaction only (outside tests
    # they have a database of their own).
    ActiveRecord::Schema.verbose = false
    load Rails.root.join("db/errors_schema.rb")
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
  end

  test "whoever isn't signed in is asked to" do
    sign_in_page = new_profile_session_path # before a request into an engine: the session's helpers keep its script name
    get admin_errors_path
    assert_redirected_to sign_in_page
  end

  test "a member who isn't the admin finds nothing there" do
    sign_in profiles(:bob)
    get root_path # signed in for what follows: a 404 writes no session cookie

    [ admin_errors_path, admin_jobs_path ].each do |page|
      get page
      assert_response :not_found, page
    end
  end

  test "the admin reads what was reported" do
    SolidErrors::Subscriber.new.report(IOError.new("the cable server went away"), handled: true, severity: :warning, context: {}, source: "test")

    sign_in @admin
    get admin_errors_path
    assert_response :success
    assert_includes response.body, "the cable server went away"
  end

  test "the admin reaches the jobs" do
    sign_in @admin
    get admin_jobs_path
    assert_response :success
  end

  # Mission Control answers in English through an I18n config of its own,
  # which knows no other language: translations first loaded under it
  # would be English alone, for every page after.
  test "the jobs page, the first to ask for a word, leaves every language loaded" do
    I18n.reload!
    sign_in @admin
    get admin_jobs_path
    assert_response :success
    assert I18n.exists?("sessions.new.title", :it), "Italian was left out"
  ensure
    I18n.reload!
  end
end
