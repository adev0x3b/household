# frozen_string_literal: true

require "test_helper"
require "rake"

# `setup:code`: the one-time code the setup page asks for, made on the machine.
class SetupCodeRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("setup:code")
    Rake::Task["setup:code"].reenable
  end

  # The installer captures standard output, so it must hold the code alone.
  test "prints the code alone on standard output, and the copy accepts it" do
    Household.find_each { |household| Households::Destroy.call(household) }

    out, err = capture_io { Rake::Task["setup:code"].invoke }

    assert_match(/\A([A-HJ-NP-Z2-9]{4}-){3}[A-HJ-NP-Z2-9]{4}\n\z/, out)
    assert_match(/\ASetup code: /, err)
    assert SetupCode.accepts?(out.strip, Platform.setup_code_digest)
  end

  # Its own status, so the installer tells "set up already" apart from a failure.
  test "refuses, exiting with 3, once anyone exists" do
    error = assert_raises(SystemExit) { capture_io { Rake::Task["setup:code"].invoke } }

    assert_equal 3, error.status
    assert_nil Platform.setup_code_digest
  end
end
