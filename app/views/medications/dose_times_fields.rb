# frozen_string_literal: true

# "Times": the doses of the day on a medication's form, under the recurrence
# fields. A stepper adds one dose or takes the last away (none means once a
# day, at no set time). Each dose is a row, "with breakfast", "with lunch",
# "with dinner", "at bedtime" or a clock time, proposed from
# the standard administration times (Events::TimesOfDay::DEFAULTS) and
# changed in place (dose-times). The rows the user set are never rewritten:
# "+" only appends one. Saved as the series' slots (EventSlot, through
# Occurrences::FormSave), as a whole, so a removed row just goes.
#
#   render Views::Medications::DoseTimesFields.new(event: occurrence.event)
#   # nil: none yet; an unsaved event (a failed save) shows the times it was given
class Views::Medications::DoseTimesFields < Views::Base
  CUSTOM = "custom"

  def initialize(event:)
    @event = event
  end

  def view_template
    fieldset(
      class: "dose-times",
      data: {
        controller: "dose-times",
        dose_times_defaults_value: Events::TimesOfDay::DEFAULTS.to_json,
        dose_times_max_value: Events::TimesOfDay::MAX_PER_DAY
      }
    ) do
      input(type: "hidden", name: "event[slots_submitted]", value: "1")
      legend(class: "label") do
        render Components::Icon.new("fa-clock", style: :regular)
        whitespace
        plain t("medications.form.times.label")
      end
      p(class: "help") { t("medications.form.times.help") }

      stepper

      div(class: "dose-times__rows", data: { dose_times_target: "rows" }) do
        entries.each { |entry| render_row(entry) }
      end

      template(data: { dose_times_target: "template" }) { render_row(nil) }
    end
  end

  private

  # What each slot was written as: its anchor ("CV"), else its clock time.
  def entries
    return [] unless @event&.timed?

    @event.slots.map { |time, anchor| anchor.presence || time }
  end

  def stepper
    div(class: "dose-times__stepper") do
      render Components::ItemAction.new(icon: "fa-minus", label: t("medications.form.times.fewer"), data: { action: "dose-times#decrement" })
      span(class: "dose-times__count", data: { dose_times_target: "count" }) { entries.size.to_s }
      render Components::ItemAction.new(icon: "fa-plus", label: t("medications.form.times.more"), data: { action: "dose-times#increment" })
      span(class: "dose-times__per-day") { t("medications.form.times.per_day") }
    end
  end

  # One dose: an anchor or "at a time" + the time, and the value that is sent.
  # The time input is rendered shown and left to dose_times_controller.js,
  # which hides or shows it for every row on connect and on each change.
  def render_row(entry)
    anchor = entry if Events::TimesOfDay.anchor?(entry)
    time = entry unless anchor
    div(class: "dose-times__row", data: { dose_times_target: "row" }) do
      div(class: "select is-small") do
        select(name: nil, aria: { label: t("medications.form.times.label") }, data: { dose_times_target: "anchor", action: "change->dose-times#sync" }) do
          Events::TimesOfDay::ANCHORS.each_key do |code|
            option(value: code, selected: code == anchor) { t("medications.anchors.#{code}") }
          end
          option(value: CUSTOM, selected: anchor.nil?) { t("medications.form.times.custom") }
        end
      end
      input(
        type: "time", value: time, class: "input is-small dose-times__time", aria: { label: t("medications.form.times.custom") },
        disabled: anchor.present?,
        data: { dose_times_target: "time", action: "input->dose-times#sync change->dose-times#sync" }
      )
      input(type: "hidden", name: "event[slots][]", value: entry, data: { dose_times_target: "value" })
      render Components::ItemAction.new(icon: "fa-xmark", label: t("medications.form.times.remove"), data: { action: "dose-times#remove" })
    end
  end
end
