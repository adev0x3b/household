# frozen_string_literal: true

# How a series repeats, on its form: how often, every how many, on which
# days of the week, and when it stops. The fields are the ones
# Events::RecurrenceRule builds a rule from, and it reads the series' rule
# back into them; an end given as a count reads back as the day it falls on.
class Views::Occurrences::EventFields < Views::Base
  # What the form offers: not repeating, then every way a rule can.
  FREQUENCIES = [ "none", *Events::RecurrenceRule::FREQUENCIES ].freeze

  # event: the series, or nil for a new one. ends_sent: the end's fields as
  # a refused form sent them, shown in place of the series' own.
  # ends_errors: what the server refused in the rule, said under whichever
  # of the end's fields is shown, since the end is what a person can set wrong.
  def initialize(event: nil, ends_sent: {}, ends_errors: [])
    @rule = Events::RecurrenceRule.fields(event&.rrule)
    @ends_sent = ends_sent.to_h.with_indifferent_access
    @ends_errors = ends_errors
  end

  def view_template
    div(
      class: "event-fields",
      data: { controller: "recurrence-fields" }
    ) do
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
      render_ends
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

  # The way it stops, then the one field that way asks for, shown and sent
  # alone (recurrence_fields_controller.js).
  def render_ends
    render Components::Field.new(label: t("event_fields.ends.label"), control_id: "event_ends_by", select: true) do
      select(
        id: "event_ends_by",
        name: "event[ends_by]",
        data: { recurrence_fields_target: "endsBy", action: "change->recurrence-fields#toggle" }
      ) do
        Events::SeriesEnd.kinds.each do |kind|
          option(value: kind.key, selected: kind.key == ends_by) { t("event_fields.ends.kinds.#{kind.key}") }
        end
      end
    end
    render_end_day
    render_end_count(Events::SeriesEnd::AfterDays, label: t("event_fields.ends.days_label"), help: t("event_fields.ends.days_help"))
    render_end_count(Events::SeriesEnd::AfterTimes, label: t("event_fields.ends.times_label"), help: t("event_fields.ends.times_help"))
  end

  def render_end_day
    render Components::Field.new(label: t("event_fields.ends.day_label"), control_id: "event_ends", required: true,
                                 errors: @ends_errors, data: end_value_data(Events::SeriesEnd::OnDate)) do |field|
      input(type: "date", id: "event_ends", name: "event[ends]", value: @ends_sent.fetch(:ends) { @rule.ends&.iso8601 }, required: true,
            class: "input is-medium", aria: field.aria)
    end
  end

  def render_end_count(kind, label:, help:)
    render Components::Field.new(label: label, control_id: "event_#{kind.param}", required: true, help: help,
                                 errors: @ends_errors, data: end_value_data(kind)) do |field|
      input(type: "number", id: "event_#{kind.param}", name: "event[#{kind.param}]", value: @ends_sent[kind.param], min: "1",
            max: Events::SeriesEnd::MOST.to_s, step: "1", inputmode: "numeric", required: true,
            class: "input is-medium", aria: field.aria)
    end
  end

  # How the series ends: as it was sent, else as its rule reads.
  def ends_by = @ends_sent[:ends_by].presence || Events::SeriesEnd.kind_of(@rule).key

  def end_value_data(kind) = { recurrence_fields_target: "endsValue", ends_by: kind.key }
end
