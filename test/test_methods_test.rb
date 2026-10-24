# frozen_string_literal: true

require "test_helper"

# Minitest runs every public method whose name starts with "test_", and a
# module a test case includes can bring such methods without meaning to:
# the route helpers do, for a route named "test", once the routes are
# drawn, so only in the tests that happen to run after something drew them.
class TestMethodsTest < ActiveSupport::TestCase
  test "every test a test case runs is written in the suite" do
    Rails.application.routes.routes # asking for them draws them, with their helpers
    suite = Rails.root.join("test").to_s

    strays = Minitest::Runnable.runnables.flat_map do |test_case|
      test_case.runnable_methods
        .reject { |name| test_case.instance_method(name).source_location&.first&.start_with?(suite) }
        .map { |name| "#{test_case.name}##{name}" }
    end

    assert_empty strays, "a module these test cases include brings methods Minitest would run as tests"
  end
end
