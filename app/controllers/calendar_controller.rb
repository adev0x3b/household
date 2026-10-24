# frozen_string_literal: true

class CalendarController < ApplicationController
  without_authorization "the viewer's own calendar: every series is read through Event.accessible_by", only: :show

  # Years the calendar opens on; outside them, or a month that isn't one, it
  # opens on today's month rather than failing (?month=13 was a 500).
  YEARS = 1900..2200

  def show
    month = Calendar::Month.new(requested_month || Date.current)
    days = Calendar::Days.between(current_profile, month.shown.first, month.shown.last)

    render_page Views::Calendar::Index.new(month: month, calendar_data: days, profile: current_profile)
  end

  private

  # The month asked for (this year's, without a year), when it is one.
  def requested_month
    month = params.fetch(:month, Date.current.month).to_i
    year = params.fetch(:year, Date.current.year).to_i
    Date.new(year, month, 1) if (1..12).cover?(month) && YEARS.cover?(year)
  end
end
