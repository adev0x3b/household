# frozen_string_literal: true

module Reports
  # The closed date range a dashboard reports on. Every figure is compared
  # with #previous, the range of the same length just before it. A trend
  # chart plots one point per bucket, and the bucket grows with the range
  # (a day, a week or a month) so that a chart keeps between four and
  # thirty-one points whether the reader picked a week or a year.
  class Period < Data.define(:start_date, :end_date)
    RECENT_DAYS = 30
    AHEAD_DAYS = 7

    Bucket = Data.define(:start_date, :end_date, :granularity) do
      def range = start_date..end_date

      def label = I18n.l(start_date, format: granularity.label_format)
    end

    class Days
      def self.label_format = "%-d %b"
      def self.starts(from, to) = (from..to).to_a
      def self.end_of(first) = first
      def self.index(date, from) = (date - from).to_i
    end

    # A week is labelled by its first day, so a weekly chart reads like a
    # daily one with gaps.
    class Weeks
      def self.label_format = "%-d %b"
      def self.starts(from, to) = (from.beginning_of_week..to).step(7).to_a
      def self.end_of(first) = first.end_of_week
      def self.index(date, from) = (date.beginning_of_week - from.beginning_of_week).to_i / 7
    end

    class Months
      def self.label_format = "%b %y"
      def self.starts(from, to) = (0..index(to, from)).map { |months| from.beginning_of_month >> months }
      def self.end_of(first) = first.end_of_month
      def self.index(date, from) = ((date.year - from.year) * 12) + date.month - from.month
    end

    # The period named by a page's `start_date` and `end_date` parameters. A
    # missing or malformed date falls back to the start or the end of the
    # current year, and dates given the wrong way round are swapped.
    def self.parse(start_param, end_param, today: Date.current)
      start_date = parse_date(start_param) || today.beginning_of_year
      end_date = parse_date(end_param) || today.end_of_year
      start_date, end_date = end_date, start_date if start_date > end_date

      new(start_date: start_date, end_date: end_date)
    end

    # The fixed spans a home page reads as of today, whatever period is
    # picked: the last 30 days (a page's period unless one is picked, and
    # how far back "overdue" looks), the next 7 days after today, and today
    # with them.
    def self.recent(today:) = new(start_date: today - (RECENT_DAYS - 1), end_date: today)
    def self.ahead(today:) = new(start_date: today + 1, end_date: today + AHEAD_DAYS)
    def self.from_today(today:) = new(start_date: today, end_date: today + AHEAD_DAYS)

    def self.parse_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
    private_class_method :parse_date

    def range = start_date..end_date

    def length_in_days = (end_date - start_date).to_i + 1

    def previous
      self.class.new(start_date: start_date - length_in_days, end_date: start_date - 1)
    end

    def granularity
      if length_in_days <= 31 then Days
      elsif length_in_days <= 184 then Weeks
      else Months
      end
    end

    def buckets
      granularity.starts(start_date, end_date).map do |first|
        last = granularity.end_of(first)
        Bucket.new(start_date: [ first, start_date ].max, end_date: [ last, end_date ].min, granularity: granularity)
      end
    end

    def bucket_labels = buckets.map(&:label)

    # Where `date` falls in #buckets, worked out from the date alone, so that
    # thousands of records can be placed without walking the list.
    def bucket_index(date)
      granularity.index(date, start_date) if range.cover?(date)
    end

    # The items sorted into the buckets they fall in, one array per bucket
    # in order, empty ones included, so that a chart has a value at every
    # point. The block gives an item's date; an item dated outside the range
    # is left out.
    def per_bucket(items)
      groups = Array.new(buckets.size) { [] }
      items.each do |item|
        index = bucket_index(yield(item))
        groups[index] << item if index
      end
      groups
    end

    def to_param
      { start_date: start_date.iso8601, end_date: end_date.iso8601 }
    end
  end
end
