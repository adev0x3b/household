# frozen_string_literal: true

require "test_helper"

class Calendar::MonthTest < ActiveSupport::TestCase
  test "shows whole weeks: the days before the 1st and after the last, from the months beside it" do
    month = Calendar::Month.new(Date.new(2026, 10, 15))

    assert_equal Date.new(2026, 10, 1), month.first_day
    assert_equal Date.new(2026, 10, 31), month.last_day
    assert_equal Date.new(2026, 9, 28), month.shown.first, "the Monday before the 1st, a Thursday"
    assert_equal Date.new(2026, 11, 1), month.shown.last, "the Sunday after the 31st, a Saturday"
    assert_equal 35, month.shown.count
  end

  test "a month that starts on a Monday and ends on a Sunday shows nothing beside it" do
    month = Calendar::Month.new(Date.new(2027, 2, 1))

    assert_equal month.days, month.shown
  end

  test "knows which shown days are the months' beside it" do
    month = Calendar::Month.new(Date.new(2026, 10, 1))

    assert month.beside?(Date.new(2026, 9, 30))
    assert month.beside?(Date.new(2026, 11, 1))
    assert_not month.beside?(Date.new(2026, 10, 1))
    assert_not month.beside?(Date.new(2026, 10, 31))
  end

  test "names the weekdays from the week's first day, in the reader's language" do
    assert_equal %w[Mon Tue Wed Thu Fri Sat Sun], Calendar::Month.weekday_names
    assert_equal %w[lun mar mer gio ven sab dom], I18n.with_locale(:it) { Calendar::Month.weekday_names }
  end
end
