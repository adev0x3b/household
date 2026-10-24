# frozen_string_literal: true

# With CLOCK_AHEAD_DAYS set, the test process lives that many days ahead of
# the machine, its clock still ticking: the suite as CI will run it then. The
# nightly year-ahead run sets it, so a test that passes only near the day it
# was written fails the night it reaches main, not on every pull request
# months later.
#
# What moves is what travel_to stubs: Time.now, Date.today and DateTime.now,
# which Time.current and Date.current read. They are redefined on the classes
# themselves rather than prepended, so a test's travel_to still replaces them
# and travel_back gives the moved clock back.
if ENV["CLOCK_AHEAD_DAYS"]
  CLOCK_AHEAD_DAYS = Integer(ENV["CLOCK_AHEAD_DAYS"])

  class << Time
    alias_method :now_on_the_machine, :now
    def now(...) = now_on_the_machine(...) + CLOCK_AHEAD_DAYS.days
  end

  class << Date
    alias_method :today_on_the_machine, :today
    def today(...) = today_on_the_machine(...) + CLOCK_AHEAD_DAYS
  end

  class << DateTime
    alias_method :now_on_the_machine, :now
    def now(...) = now_on_the_machine(...) + CLOCK_AHEAD_DAYS
  end
end
