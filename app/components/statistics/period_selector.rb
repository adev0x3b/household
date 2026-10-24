# frozen_string_literal: true

# The dates a dashboard page reports on, as one control on the page: a
# button naming the period (a shortcut's name when it is one, else its two
# dates) that opens the shortcuts and, under them, two dates to apply
# (dropdown_controller.js). It knows no page: each hands it its own
# address (`url`, with no query) and the filters that must survive every
# period change (`params`, the member filter say).
class Components::Statistics::PeriodSelector < Components::Base
  Shortcut = Data.define(:key, :start_date, :end_date)

  def initialize(start_date:, end_date:, url:, params: {})
    @start_date = start_date
    @end_date = end_date
    @url = url
    @params = params
  end

  def view_template
    div(class: "stat-period-selector", data: { controller: "dropdown" }) do
      button(type: "button", class: "stat-period-selector__button", aria: { expanded: "false" },
             data: { dropdown_target: "toggler", action: "click->dropdown#toggle" }) do
        render Components::Icon.new("fa-calendar-days")
        span(class: "is-sr-only") { t("statistics.period_selector.label") }
        span(class: "stat-period-selector__name") { name }
        render Components::Icon.new("fa-chevron-down", class: "stat-period-selector__chevron")
      end

      div(class: "stat-period-selector__menu", data: { dropdown_target: "menu" }) do
        shortcuts.each { |shortcut| shortcut_link(shortcut) }
        custom_range_form
      end
    end
  end

  private

  def name
    current = shortcuts.find { |shortcut| current?(shortcut) }
    current ? t("statistics.period_selector.#{current.key}") : dates
  end

  # Two dates, with their year only when it isn't this one.
  def dates
    format = [ @start_date, @end_date ].all? { _1.year == Date.current.year } ? :short : :long
    "#{l(@start_date, format: format)} – #{l(@end_date, format: format)}"
  end

  # The previous and next month step from the period picked, so a reader
  # can walk back through the year a month at a time.
  def shortcuts
    today = Date.current
    [
      Shortcut.new(:last_30_days, today - 29.days, today),
      Shortcut.new(:current_month, today.beginning_of_month, today.end_of_month),
      Shortcut.new(:previous_month, @start_date.prev_month.beginning_of_month, @start_date.prev_month.end_of_month),
      Shortcut.new(:next_month, @start_date.next_month.beginning_of_month, @start_date.next_month.end_of_month),
      Shortcut.new(:current_year, today.beginning_of_year, today.end_of_year)
    ]
  end

  def current?(shortcut) = @start_date == shortcut.start_date && @end_date == shortcut.end_date

  def shortcut_link(shortcut)
    current = current?(shortcut)
    query = @params.merge(start_date: shortcut.start_date.iso8601, end_date: shortcut.end_date.iso8601).to_query

    a(href: "#{@url}?#{query}", class: [ "stat-period-selector__shortcut", ("is-current" if current) ], aria: { current: ("true" if current) },
      data: { turbo_action: "replace", action: "click->dropdown#close" }) { t("statistics.period_selector.#{shortcut.key}") }
  end

  def custom_range_form
    form(action: @url, method: :get, class: "stat-period-selector__custom",
         data: { turbo_action: "replace", action: "submit->dropdown#close" }) do
      @params.each { |name, value| input(type: "hidden", name: name.to_s, value: value) }
      date_field(:start_date, @start_date, t("statistics.period_selector.from"))
      date_field(:end_date, @end_date, t("statistics.period_selector.to"))
      button(type: "submit", class: "stat-period-selector__apply") { t("statistics.period_selector.apply") }
    end
  end

  def date_field(name, value, label)
    label(class: "stat-period-selector__field") do
      span { label }
      input(type: "date", name: name.to_s, value: value.iso8601, class: "stat-period-selector__date-input")
    end
  end
end
