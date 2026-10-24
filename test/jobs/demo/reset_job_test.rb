# frozen_string_literal: true

require "test_helper"
require "fugit" # what Solid Queue reads a schedule with

class Demo::ResetJobTest < ActiveJob::TestCase
  test "it rebuilds the demo household where there is one, and only there" do
    runs = 0
    swapping(Demo::ResetJob, :seed!, -> { runs += 1 }) do
      Demo::ResetJob.perform_now
      assert_equal 0, runs

      demo_household
      Demo::ResetJob.perform_now
      assert_equal 1, runs
    end
  end

  test "a rebuild that fails is a failed job" do
    demo_household
    swapping(Demo::ResetJob, :seed!, -> { false }) do
      assert_raises(RuntimeError) { Demo::ResetJob.perform_now }
    end
  end

  # Read as Solid Queue reads it (ERB, then YAML), once per destination.
  def reset_task_on(destination)
    schedule = Rails.root.join("config/recurring.yml")
    with_env("KAMAL_DESTINATION" => destination) do
      ActiveSupport::ConfigurationFile.parse(schedule).dig("production", "reset_demo_household")
    end
  end

  test "it is scheduled every night on the demo installation, and nowhere else" do
    task = reset_task_on("demo")
    assert_equal "Demo::ResetJob", task["class"]
    assert_equal [ "*", "*", "*" ], Fugit.parse(task["schedule"]).to_cron_s.split.last(3), "every day"

    %w[production staging dev].each { |destination| assert_nil reset_task_on(destination), "#{destination} keeps its data" }
  end
end
