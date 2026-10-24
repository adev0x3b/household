# frozen_string_literal: true

# A month of the calendar as a grid of weeks, one Views::Calendar::DayCard
# per day, the first and last weeks filled in with the days of the months
# beside it; the month picker is the top bar's.
class Views::Calendar::Index < Views::Base
  def initialize(month:, calendar_data:, profile:)
    @month = month
    @calendar_data = calendar_data
    @profile = profile
  end

  def page_title = t("navbar.links.calendar")

  def navbar_controls = Views::Calendar::Navigation.new(date: @month.first_day)

  def view_template
    div(class: "calendar", data: {
          controller: "calendar-subscription calendar-today",
          calendar_subscription_profile_id_value: @profile.id,
          calendar_subscription_year_value: @month.year,
          calendar_subscription_month_value: @month.month
        }) do
      # The month picker in the bar says where the reader is; the heading
      # names the page for assistive technology.
      h1(class: "page-title is-sr-only") { t("navbar.links.calendar") }
      render Views::Calendar::DayMenus.new do
        div(class: "calendar__grid") do
          weekday_headings
          render_days
        end
      end
    end
  end

  private

  # The grid's columns, where the screen is wide enough for a week to be a
  # row; each card names its own day, so these are decoration to a reader
  # who can't see the columns.
  def weekday_headings
    ::Calendar::Month.weekday_names.each do |name|
      div(class: "calendar__weekday", aria: { hidden: "true" }) { name }
    end
  end

  def render_days
    @month.shown.each do |day|
      render Views::Calendar::DayCard.new(
        date: day,
        occurrences: @calendar_data[day] || [],
        today: day == Date.current,
        beside: @month.beside?(day),
        viewer: @profile
      )
    end
  end
end
