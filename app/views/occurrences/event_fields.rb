# frozen_string_literal: true

# How a series repeats, on its form: how often, every how many, on which
# days of the week. The fields are the ones Events::RecurrenceRule builds
# a rule from, and it reads the series' rule back into them.
class Views::Occurrences::EventFields < Views::Base
  # What the form offers: not repeating, then every way a rule can.
  FREQUENCIES = [ "none", *Events::RecurrenceRule::FREQUENCIES ].freeze

  # event: the series, or nil for a new one.
  def initialize(event: nil)
    @rule = Events::RecurrenceRule.fields(event&.rrule)
  end

  def view_template
    div(
      class: "event-fields",
      data: { controller: "recurrence-fields" }
    ) do
      # The day it stops repeating has no field yet: kept as it is.
      input(type: "hidden", name: "event[ends]", value: @rule.ends.iso8601) if @rule.ends
      render_frequency_field
      render_details
    end
  end

  private

  def render_frequency_field
    render Components::Field.new(label: t("event_fields.frequency_label"), control_id: "event_frequency", select: true) do
      select(
        id: "event_frequency",
        name: "event[frequency]",
        data: { recurrence_frequency: true, action: "change->recurrence-fields#toggle" }
      ) do
        FREQUENCIES.each do |frequency|
          option(value: frequency, selected: frequency == @rule.frequency) do
            t("event_fields.frequencies.#{frequency}")
          end
        end
      end
    end
  end

  # Shown only while the series repeats (recurrence_fields_controller.js).
  def render_details
    div(data: { recurrence_fields_target: "details" }) do
      render_interval_field
      render_weekly_days
    end
  end

  def render_interval_field
    render Components::Field.new(label: t("event_fields.interval_label"), control_id: "event_interval",
                                 help: t("event_fields.interval_help")) do
      input(
        type: "number",
        id: "event_interval",
        name: "event[interval]",
        value: @rule.interval.to_s,
        min: "1",
        max: "365",
        class: "input is-medium",
        placeholder: t("event_fields.interval_placeholder")
      )
    end
  end

  # A rule's day ("monday") by its short name in the reader's language.
  def day_label(day) = t("date.abbr_day_names").fetch(Date::DAYNAMES.index(day.capitalize)).upcase_first

  def render_weekly_days
    fieldset(class: "field", data: { recurrence_fields_target: "weeklyDays" }) do
      legend(class: "label") { t("event_fields.weekly_days_label") }
      div(class: "event-fields__days") do
        Events::RecurrenceRule::WEEK_DAYS.each do |day|
          label(class: "event-fields__day-label") do
            input(
              type: "checkbox",
              name: "event[week_days][]",
              value: day,
              checked: @rule.week_days.include?(day),
              class: "event-fields__day-checkbox"
            )
            span { day_label(day) }
          end
        end
      end
    end
  end
end
