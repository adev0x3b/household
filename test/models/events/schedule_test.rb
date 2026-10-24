# frozen_string_literal: true

require "test_helper"

# A stored series is read by more than one process: a production copy
# restored on a laptop in Rome, a self-hoster's container started with TZ
# set, the tests on a machine east of UTC. Rails' own zone is the same for
# all of them; the process's clock zone (TZ) is not, and a series' days
# must not follow it.
class Events::ScheduleTest < ActiveSupport::TestCase
  test "a series that ends on 2 April ends on 2 April whatever the process's zone" do
    line = with_env("TZ" => "UTC") { Events::RecurrenceRule.build(frequency: "daily", ends: "2027-04-02") }

    %w[UTC Europe/Rome Pacific/Kiritimati America/Los_Angeles].each do |zone|
      with_env("TZ" => zone) do
        assert_equal Date.new(2027, 4, 2), Events::Schedule.new(Date.new(2027, 3, 30), line).dates_between(Date.new(2027, 3, 30), Date.new(2027, 4, 10)).last, zone
        assert_equal Date.new(2027, 4, 2), Events::RecurrenceRule.describe(line)[:ends], zone
      end
    end
  end

  test "an end written under any zone is the line production writes" do
    lines = %w[UTC Europe/Rome Pacific/Kiritimati America/Los_Angeles].map do |zone|
      with_env("TZ" => zone) { Events::RecurrenceRule.build(frequency: "daily", ends: "2027-04-02") }
    end

    assert_equal [ "FREQ=DAILY;UNTIL=20270402T235959Z" ], lines.uniq
  end

  test "a weekly series falls on its weekdays, and the next date follows the day asked about, in any zone" do
    line = "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH"
    expected = [ Date.new(2026, 3, 2), Date.new(2026, 3, 5), Date.new(2026, 3, 16), Date.new(2026, 3, 19), Date.new(2026, 3, 30) ]

    %w[UTC Pacific/Kiritimati America/Los_Angeles].each do |zone|
      with_env("TZ" => zone) do
        Time.use_zone("America/New_York") do
          schedule = Events::Schedule.new(Date.new(2026, 3, 2), line)

          assert_equal expected, schedule.dates_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31)), zone
          assert_equal [ Date.new(2026, 3, 5), Date.new(2026, 3, 16) ], schedule.dates_after(Date.new(2026, 3, 2), 2), zone
        end
      end
    end
  end

  test "the first date from a day on is counted from the series' own first day, that day included" do
    fortnightly = Events::Schedule.new(Date.new(2026, 9, 7), "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO")

    assert_equal Date.new(2026, 10, 19), fortnightly.first_date_from(Date.new(2026, 10, 7))
    assert_equal Date.new(2026, 10, 19), fortnightly.first_date_from(Date.new(2026, 10, 19)), "the day itself counts"
    assert_equal Date.new(2026, 11, 20), Events::Schedule.new(Date.new(2026, 1, 20), "FREQ=MONTHLY").first_date_from(Date.new(2026, 10, 21))
    assert_nil Events::Schedule.new(Date.new(2026, 10, 1), Events::RecurrenceRule.build(frequency: "daily", ends: "2026-10-06")).first_date_from(Date.new(2026, 10, 7))
  end
end
