# frozen_string_literal: true

module Events
  # When a repeating series stops, as its form says it: never, on a day,
  # or after a number of the days it happens on.
  # Each way gives the series' last day, which its rule keeps as its end,
  # so a series reads back as ending on that day however it was said.
  #
  #   Events::SeriesEnd.from(ends_by: "after_count", ends_after: "15")
  #     .last_day(starts_on: Date.new(2026, 11, 1), rrule: "FREQ=DAILY")
  #   # => Sun, 15 Nov 2026
  module SeriesEnd
    # The most days or times a count may be: past it a series is better
    # left without an end, and the walk for the last of its days stays short.
    MOST = 999

    # What a form sends about the end: the way it chose, and each way's field.
    PARAMS = %i[ends_by ends ends_after].freeze

    def self.kinds = [ Never, OnDate, AfterCount ]

    # The end a form's fields describe. A form from before the choice
    # existed sends only the day it ends, or nothing.
    def self.from(params)
      params = params.to_h.with_indifferent_access
      kind = kinds.find { |candidate| candidate.key == params[:ends_by] }
      kind ||= params[:ends].present? ? OnDate : Never
      kind.new(params)
    end

    # How a stored rule's end reads on the form: the day it ends, if it has one.
    def self.kind_of(fields) = fields.ends ? OnDate : Never

    class Never
      def self.key = "never"

      def initialize(_params); end

      def last_day(**) = nil
      def error(**) = nil
    end

    class OnDate
      def self.key = "on_date"

      def initialize(params)
        @value = params[:ends].to_s
      end

      def last_day(**) = day

      def error(starts_on:)
        return :day_missing unless day

        :before_start if starts_on && day < starts_on
      end

      private

      def day
        Date.iso8601(@value)
      rescue Date::Error
        nil
      end
    end

    # The days the series falls on, each counted once however many times
    # of the day it has: twice a day for ten days is ten. On a series that
    # happens every day that is a number of days, its first counted, so
    # fifteen from the first of the month end on the fifteenth.
    class AfterCount
      def self.key = "after_count"

      def initialize(params)
        @value = params[:ends_after].to_s
      end

      def last_day(starts_on:, rrule:) = Events::Schedule.new(starts_on, rrule).dates_after(starts_on.prev_day, count).last

      def error(**)
        :count_out_of_range unless count&.between?(1, MOST)
      end

      private

      def count = Integer(@value, 10, exception: false)
    end
  end
end
