# frozen_string_literal: true

require "test_helper"

# Every step of the first setup has the view that draws it, and answers
# what the form asks of a step.
class SetupStepsTest < ActiveSupport::TestCase
  test "each step in Setup::STEPS has its view and the step's whole interface" do
    Setup::STEPS.each do |step|
      assert Views::Setup::Steps::BY_STEP.key?(step), "#{step} has no view in Views::Setup::Steps::BY_STEP"
      assert_kind_of Symbol, step.param_key
      assert_kind_of Array, step.fields
      instance = step.for_setup
      assert_same instance, instance.assign({}), "#{step}#assign returns the step"
      assert_includes [ true, false ], instance.asked?(Setup::Form.new)
      assert_respond_to instance, :errors
    end
    assert_equal Setup::STEPS.sort_by(&:name), Views::Setup::Steps::BY_STEP.keys.sort_by(&:name)
  end
end
