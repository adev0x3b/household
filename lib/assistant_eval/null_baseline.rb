# frozen_string_literal: true

# A scenario whose checks already hold before anyone says anything would
# pass for a model that does nothing: its checks are too lenient to mean
# anything. Seeds the sandbox, sends no message, evaluates the checks —
# no model involved, always rolled back. Run for every scenario by the test
# suite, and for the one being edited in the dashboard.
module AssistantEval
  module NullBaseline
    module_function

    def lenient?(scenario)
      lenient = false
      ActiveRecord::Base.transaction do
        profile = Sandbox.profile!
        Seeds.apply(scenario.seed, profile)
        lenient = Expectations.new(profile).failures(scenario.expect).empty?
        raise ActiveRecord::Rollback
      end
      lenient
    end
  end
end
