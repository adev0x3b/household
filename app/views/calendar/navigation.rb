# frozen_string_literal: true

class Views::Calendar::Navigation < Views::Base
  def initialize(date:)
    @date = date
  end

  def view_template
    nav(class: "calendar-nav") do
      prev_button
      month_year_selector
      next_button
    end
  end

  private

  def prev_button
    prev_date = @date.prev_month
    a(
      href: calendar_path(month: prev_date.month, year: prev_date.year),
      class: "calendar-nav__btn",
      aria: { label: t("calendar.navigation.previous_month") },
      data: { turbo_action: "replace" }
    ) do
      render Components::Icon.new("fa-chevron-left")
    end
  end

  def next_button
    next_date = @date.next_month
    a(
      href: calendar_path(month: next_date.month, year: next_date.year),
      class: "calendar-nav__btn",
      aria: { label: t("calendar.navigation.next_month") },
      data: { turbo_action: "replace" }
    ) do
      render Components::Icon.new("fa-chevron-right")
    end
  end

  def month_year_selector
    div(class: "calendar-nav__selector") do
      render Components::AutoSubmitForm.new(
        url: calendar_path,
        dom_id: "calendar_nav",
        html_class: "calendar-nav__form",
        turbo_action: "replace"
      ) do |form|
        form.select_field(name: "month", html_class: "calendar-nav__select calendar-nav__select--month", label: t("calendar.navigation.month")) { month_options }
        span(class: "calendar-nav__divider")
        form.select_field(name: "year", html_class: "calendar-nav__select calendar-nav__select--year", label: t("calendar.navigation.year")) { year_options }
      end
    end
  end

  # A month's name stands alone in the picker, so it starts with a capital
  # even in a language that writes it in lower case ("gennaio").
  def month_options
    t("date.month_names").drop(1).each.with_index(1) do |name, month|
      option(value: month, selected: month == @date.month) { name.upcase_first }
    end
  end

  def year_options
    this_year = Date.current.year
    ((this_year - 2)..(this_year + 5)).each do |year|
      option(value: year, selected: year == @date.year) { year.to_s }
    end
  end
end
