# frozen_string_literal: true

# Counts the requests the test server is answering, so that a system test can
# wait for its browser's last ones before the next test begins. The server
# answers them on its own threads, and a request a page sent as its test
# ended would otherwise go on into the next test's database transaction.
class InFlightRequests
  @count = Concurrent::AtomicFixnum.new(0)

  class << self
    attr_reader :count

    def wait_until_idle(within: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
      sleep 0.01 until count.value.zero? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    self.class.count.increment
    @app.call(env)
  ensure
    self.class.count.decrement
  end
end
