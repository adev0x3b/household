# frozen_string_literal: true

# "Remind me": the signed-in person's own reminders on a series, under the
# recurrence fields of every kind's form. One row per reminder (an amount
# and hours or days before), added and removed in place (nested-fields);
# saved by Occurrences::FormSave as the whole set, so a removed row just goes.
# Each person who has the series sees and keeps only theirs.
#
#   render Views::Occurrences::ReminderFields.new(reminders: event.reminders_of(viewer))   # none yet: []
class Views::Occurrences::ReminderFields < Views::Base
  def initialize(reminders:)
    @reminders = reminders
  end

  def view_template
    fieldset(class: "reminder-fields") do
      input(type: "hidden", name: "event[reminders_submitted]", value: "1")
      legend(class: "label") do
        render Components::Icon.new("fa-bell", style: :regular)
        whitespace
        plain t("reminders.form.label")
      end
      p(class: "help") { t("reminders.form.help") }

      render Components::NestedFields.new(rows_class: "reminder-fields__rows", row_class: "reminder-fields__row", prefix: ->(index) { "event[reminders][#{index}]" },
                                          add_label: t("reminders.form.add"), remove_label: t("reminders.form.remove"), saved_whole: true, danger: false) do |fields|
        fields.rows { @reminders.each_with_index { |reminder, index| render_row(fields, *reminder.amount_and_unit, index: index) } }
        fields.template { render_row(fields, 1, "days", index: Components::NestedFields::NEW_ROW) }
      end
    end
  end

  private

  def render_row(fields, amount, unit, index:)
    fields.row(index: index) do |prefix|
      input(
        type: "number", name: "#{prefix}[amount]", value: amount, min: 1, max: EventReminder::MAX_OFFSET / 60, step: 1,
        required: true, class: "input is-small reminder-fields__amount", aria: { label: t("reminders.form.amount") }
      )
      div(class: "select is-small") do
        select(name: "#{prefix}[unit]", aria: { label: t("reminders.form.unit") }) do
          EventReminder::UNITS.each_key do |name|
            option(value: name, selected: name == unit) { t("reminders.units.#{name}") }
          end
        end
      end
      span(class: "reminder-fields__before") { t("reminders.form.before") }
    end
  end
end
