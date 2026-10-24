# frozen_string_literal: true

require "test_helper"

class Reports::PeriodTest < ActiveSupport::TestCase
  test "parse defaults to the current year" do
    result = Reports::Period.parse(nil, nil, today: Date.new(2026, 5, 10))

    assert_equal Date.new(2026, 1, 1), result.start_date
    assert_equal Date.new(2026, 12, 31), result.end_date
  end

  test "parse swaps a reversed range and ignores invalid dates" do
    assert_equal period(Date.new(2026, 1, 1), Date.new(2026, 2, 1)), Reports::Period.parse("2026-02-01", "2026-01-01")
    assert_equal Date.new(2026, 1, 1), Reports::Period.parse("not-a-date", nil, today: Date.new(2026, 5, 10)).start_date
  end

  test "previous is the equal-length range right before" do
    march = period(Date.new(2026, 3, 1), Date.new(2026, 3, 31))

    assert_equal period(Date.new(2026, 1, 29), Date.new(2026, 2, 28)), march.previous
    assert_equal march.length_in_days, march.previous.length_in_days
  end

  test "a bucket is a day, a week or a month, by the range's length" do
    assert_equal Reports::Period::Days, period(Date.new(2026, 3, 1), Date.new(2026, 3, 31)).granularity
    assert_equal Reports::Period::Weeks, period(Date.new(2026, 1, 1), Date.new(2026, 3, 31)).granularity
    assert_equal Reports::Period::Months, period(Date.new(2026, 1, 1), Date.new(2026, 12, 31)).granularity
  end

  test "bucket_index agrees with buckets for every day in the range" do
    [ period(Date.new(2026, 3, 1), Date.new(2026, 3, 31)), period(Date.new(2026, 1, 10), Date.new(2026, 3, 31)),
      period(Date.new(2025, 11, 15), Date.new(2026, 12, 31)) ].each do |range|
      buckets = range.buckets
      range.range.each do |date|
        assert buckets[range.bucket_index(date)].range.cover?(date), "#{date} in #{range.granularity}"
      end
      assert_equal range.start_date, buckets.first.start_date
      assert_equal range.end_date, buckets.last.end_date
    end
  end

  test "bucket_index is nil outside the range" do
    assert_nil period(Date.new(2026, 3, 1), Date.new(2026, 3, 31)).bucket_index(Date.new(2026, 4, 1))
  end

  test "labels a day or a week by its first day, and a month by its name" do
    days = period(Date.new(2026, 3, 1), Date.new(2026, 3, 3))
    weeks = period(Date.new(2026, 1, 7), Date.new(2026, 3, 31))
    months = period(Date.new(2025, 11, 15), Date.new(2026, 12, 31))

    I18n.with_locale(:en) do
      assert_equal [ "1 Mar", "2 Mar", "3 Mar" ], days.bucket_labels
      assert_equal [ "7 Jan", "12 Jan" ], weeks.bucket_labels.first(2)
      assert_equal [ "Nov 25", "Dec 25", "Jan 26" ], months.bucket_labels.first(3)
    end
  end

  test "sorts items into their buckets, keeps the empty ones and drops what falls outside" do
    march = period(Date.new(2026, 3, 1), Date.new(2026, 3, 3))
    items = [
      [ Date.new(2026, 3, 3), :third ], [ Date.new(2026, 3, 1), :first ],
      [ Date.new(2026, 4, 1), :outside ], [ Date.new(2026, 3, 1), :also_first ]
    ]
    buckets = march.per_bucket(items, &:first)

    assert_equal([ %i[first also_first], [], %i[third] ], buckets.map { |bucket| bucket.map(&:last) })
  end
end
