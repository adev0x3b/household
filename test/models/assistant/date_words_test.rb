# frozen_string_literal: true

require "test_helper"

class Assistant::DateWordsTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 23) # a Wednesday

  test "the user's own words become the right day, in English and Italian" do
    {
      "2026-09-25" => "2026-09-25", "today" => "2026-09-23", "ieri" => "2026-09-22",
      "a week ago" => "2026-09-16", "about a week ago" => "2026-09-16", "una settimana fa" => "2026-09-16",
      "3 days ago" => "2026-09-20", "2 settimane fa" => "2026-09-09", "in 3 days" => "2026-09-26",
      "last Friday" => "2026-09-18", "venerdì scorso" => "2026-09-18",
      "this Friday" => "2026-09-25", "Friday" => "2026-09-25", "next Friday" => "2026-10-02",
      "last month" => "2026-08-23", "today's" => "2026-09-23", "Friday," => "2026-09-25",
      "the day before yesterday" => "2026-09-21", "l'altro ieri" => "2026-09-21",
      "last week" => "2026-09-16", "la settimana prossima" => "2026-09-30"
    }.each do |words, expected|
      assert_equal Date.iso8601(expected), Assistant::DateWords.parse(words, today: TODAY), words
    end
    assert_nil Assistant::DateWords.parse("sometime", today: TODAY)
    assert_nil Assistant::DateWords.parse(" ?! ", today: TODAY)
  end

  test "calendar dates with a month name, with or without the year" do
    { "September 25, 2026" => "2026-09-25", "on September 25" => "2026-09-25", "25th of Sept" => "2026-09-25",
      "25 settembre 2026" => "2026-09-25", "Oct 2" => "2026-10-02" }.each do |words, expected|
      assert_equal Date.iso8601(expected), Assistant::DateWords.parse(words, today: TODAY), words
    end
    assert_nil Assistant::DateWords.parse("September 31", today: TODAY)
    assert_nil Assistant::DateWords.parse("may be later", today: TODAY)
  end

  test "drafts resolve date words in their date fields" do
    travel_to TODAY.in_time_zone.change(hour: 12) do
      payload = Assistant::Draft.normalize_payload("lab_test_result", "date" => "a week ago")
      assert_equal "2026-09-16", payload.dig("lab_test_result", "date")
    end
  end
end
