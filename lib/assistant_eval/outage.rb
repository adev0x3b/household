# frozen_string_literal: true

# The model server went away in the middle of a run. Rather than burn every
# remaining scenario as an error (a whole run scored on the few that ran
# before the outage), the task waits here, asking the provider every `poll`
# seconds (AssistantEval::Preflight) until it answers again or `limit`
# seconds have passed in all.
#
#   waited = Outage.wait(limit: 1800, poll: 15)   # seconds waited, or nil when it gave up
module AssistantEval
  module Outage
    module_function

    def wait(limit:, poll:, sleeper: ->(seconds) { sleep(seconds) })
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        return nil if elapsed >= limit

        sleeper.call([ poll, limit - elapsed ].min)
        begin
          Preflight.check!(provider: Assistant.provider, model: Assistant.model)
          return Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        rescue Preflight::Unavailable
          next
        end
      end
    end
  end
end
