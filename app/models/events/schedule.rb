# frozen_string_literal: true

module Events
  # The dates a series falls on: its first day and its rule line, walked by
  # ice_cube. ice_cube counts in times while a rule is about dates, so each
  # date is read as its midnight in UTC (RecurrenceRule.midnight): the same
  # stored line then gives the same days whatever zone the process runs in.
  class Schedule
    def initialize(starts_on, rrule)
      @ice_cube = IceCube::Schedule.new(RecurrenceRule.midnight(starts_on))
      @ice_cube.add_recurrence_rule(RecurrenceRule.parse(rrule)) if rrule.present?
    end

    # Every date from one day to another, both included.
    def dates_between(from, to)
      @ice_cube.occurrences_between(RecurrenceRule.midnight(from), RecurrenceRule.midnight(to).end_of_day).map(&:to_date)
    end

    # The next `count` dates after a day.
    def dates_after(date, count)
      @ice_cube.next_occurrences(count, RecurrenceRule.midnight(date).end_of_day).map(&:to_date)
    end

    # The first date from a day on, that day included, nil when none is
    # left. A line counts from where the series began (every other week
    # from the week it started, the 5th of every month), so a series going
    # on under a new line keeps its footing.
    def first_date_from(date) = dates_after(date.prev_day, 1).first
  end
end
