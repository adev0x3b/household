# frozen_string_literal: true

module Calendar
  # A month as the calendar shows it: its own days, and the days of the
  # months beside it that complete its first and last weeks, so a week is a
  # row and no cell is blank. The month's live updates cover the same days,
  # since the page showing them is this month's.
  #
  #   month = Calendar::Month.new(Date.new(2026, 10, 1))
  #   month.shown          # => Mon 28 Sep .. Sun 1 Nov
  #   month.beside?(date)  # true for a day shown from the month before or after
  class Month
    attr_reader :first_day

    def initialize(date)
      @first_day = date.beginning_of_month
    end

    def year = @first_day.year
    def month = @first_day.month
    def last_day = @first_day.end_of_month

    def days = first_day..last_day

    # Every day on the page, the first week's and the last week's filled in.
    def shown = first_day.beginning_of_week..last_day.end_of_week

    def beside?(date) = !days.cover?(date)

    # The grid's column headings, from the week's first day.
    def self.weekday_names = I18n.t("date.abbr_day_names").rotate(Date.beginning_of_week == :monday ? 1 : 0)
  end
end
