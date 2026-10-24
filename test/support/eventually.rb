# frozen_string_literal: true

# Waiting on what another process does (a signal reaching it, its state
# changing): the condition, polled until it holds or the time is up — never
# a bare sleep, too short on a busy machine and too long on an idle one.
module Eventually
  def assert_eventually(message = nil, within: 2, every: 0.01)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
    until yield
      flunk(message || "still not so after #{within}s") if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep every
    end
    pass
  end
end
