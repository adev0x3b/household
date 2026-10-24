# frozen_string_literal: true

require "test_helper"
require "rake"

# `admin:create`: the first household and its admin on a fresh database.
class AdminRakeTest < ActiveSupport::TestCase
  isolate_env "USERNAME", "EMAIL", "PASSWORD", "HOUSEHOLD"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("admin:create")
    Rake::Task["admin:create"].reenable
  end

  # The task run with these values, and nothing for the ones left out.
  def with(**values)
    with_env(values.transform_keys { _1.to_s.upcase }) { capture_io { Rake::Task["admin:create"].invoke } }
  end

  test "creates a household owned by its admin, who can sign in" do
    assert_difference [ -> { Household.count }, -> { Profile.admin.count } ], 1 do
      with(username: "ops", email: "ops@example.com", password: "a-long-password", household: "Casa Ops")
    end

    household = Household.find_by!(name: "Casa Ops")
    admin = household.owner
    assert_predicate admin, :admin?
    assert_equal "ops", admin.username
    assert admin.valid_password?("a-long-password")
    assert_not admin.invitation_pending?
  end

  test "creates nothing when a value is missing or taken" do
    assert_no_difference -> { Household.count } do
      error = assert_raises(SystemExit) { with(username: "ops", email: "ops@example.com") }
      assert_match(/PASSWORD/, error.message) if error.message.present?
    end

    assert_no_difference [ -> { Household.count }, -> { Profile.count } ] do
      assert_raises(SystemExit) { with(username: profiles(:alice).username, email: "new@example.com", password: "a-long-password") }
    end
  end
end
