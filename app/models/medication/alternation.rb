# frozen_string_literal: true

class Medication
  # Which side an injection falls on: the series alternates from its
  # starting side dose by dose, and slot by slot within a day. The side of a
  # dose is its place in the series counted from the first, so the schedule
  # is walked once per series and kept, however many doses a month of cards
  # asks about.
  class Alternation
    def initialize(medication)
      @medication = medication
    end

    def side_on(occurrence)
      starting_side = @medication.details.side
      return starting_side unless @medication.recurring?

      doses_before(occurrence).even? ? starting_side : Medication::Details.opposite_side(starting_side)
    end

    private

    # A dose at a time off the series' slots, or on a day moved off the
    # schedule, counts as the first dose of its day.
    def doses_before(occurrence)
      day = dates_through(occurrence.date).index(occurrence.date)
      return 0 if day.nil?

      times = @medication.slots.map(&:first)
      (day * times.size) + (times.index(occurrence.time_string) || 0)
    end

    # The schedule's dates from the start through `date`, extended when a
    # later date is asked for and recomputed when the series' rule changes.
    def dates_through(date)
      schedule = @medication.schedule
      unless schedule.equal?(@schedule) && @through && date <= @through
        @schedule = schedule
        @through = [ date, @through ].compact.max
        @dates = schedule.dates_between(@medication.starts_on, @through)
      end
      @dates
    end
  end
end
