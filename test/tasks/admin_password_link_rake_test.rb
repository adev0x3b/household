# frozen_string_literal: true

require "test_helper"
require "rake"

# `admin:password_link`: a link printed on the server, the admin's way back
# to an account the mail never offers them.
class AdminPasswordLinkRakeTest < ActiveSupport::TestCase
  isolate_env "USERNAME"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("admin:password_link")
    Rake::Task["admin:password_link"].reenable
  end

  def run_task(username) = with_env("USERNAME" => username) { capture_io { Rake::Task["admin:password_link"].invoke } }.first

  test "prints a link that sets the password once, for half an hour, and ends the one made before" do
    alice = profiles(:alice).tap(&:admin!)
    earlier = alice.password_link_token!

    printed = run_task("ALICE")
    token = printed[/reset_password_token=([^\s&]+)/, 1]

    assert_match %r{\Ahttp://example\.com/profiles/password/edit\?reset_password_token=}, printed.lines.last
    assert_equal alice, Profile.with_reset_password_token(token)
    assert_nil Profile.with_reset_password_token(earlier)
    travel Profile::SHORT_PASSWORD_LINK_FOR + 1.second
    assert_not Profile.with_reset_password_token(token).reset_password_period_valid?
  end

  test "needs a username someone here goes by" do
    assert_raises(SystemExit) { run_task("") }
    assert_raises(SystemExit) { run_task("nobody") }
  end
end
