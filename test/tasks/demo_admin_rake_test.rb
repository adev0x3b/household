# frozen_string_literal: true

require "test_helper"
require "rake"

# `demo:admin`: an admin with the demo's password, which is public, so
# only where nobody outside can reach it.
class DemoAdminRakeTest < ActiveSupport::TestCase
  isolate_env "KAMAL_DESTINATION", "DEMO_PASSWORD"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:admin")
    Rake::Task["demo:admin"].reenable
  end

  def run_task = capture_io { Rake::Task["demo:admin"].invoke }

  test "on dev, makes the admin with the demo's password" do
    with_env("KAMAL_DESTINATION" => "dev") do
      assert_difference -> { Profile.admin.count } do
        run_task
      end
    end

    admin = Profile.admin.find_by!(username: "admin")
    assert admin.valid_password?(Platform.demo_password)
  end

  test "refused on every other destination, the public demo first" do
    %w[demo staging production].each do |destination|
      Rake::Task["demo:admin"].reenable
      with_env("KAMAL_DESTINATION" => destination) do
        assert_no_difference -> { Profile.count }, destination do
          assert_raises(SystemExit) { run_task }
        end
      end
    end
  end

  test "refused on a copy that says nothing of where it runs, outside development" do
    assert_no_difference -> { Profile.count } do
      assert_raises(SystemExit) { run_task }
    end
  end
end
