# frozen_string_literal: true

# "Remind me": the signed-in person's own reminders on a series, under the
# recurrence fields of every kind's form. One row per reminder (an amount
# and hours or days before, and whether it comes by email too), added and
# removed in place (nested-fields); saved by Occurrences::FormSave as the
# whole set, so a removed row just goes. Each person who has the series
# sees and keeps only theirs.
#
#   render Views::Occurrences::ReminderFields.new(reminders: event.reminders_of(viewer), mail: Emails.for_reminders(viewer))
#
# The box for email is drawn only where mail can reach the person
# (mail: :available); while their address waits to be confirmed, a line
# says where to confirm it, and a row without the box leaves its reminder's
# email as it was (Events::SetReminders).
class Views::Occurrences::ReminderFields < Views::Base
  # mail: Emails.for_reminders for the viewer.
  def initialize(reminders:, mail: :off)
    @reminders = reminders
    @mail = mail
  end

  def view_template
    fieldset(class: [ "reminder-fields", ("reminder-fields--email" if @mail == :available) ]) do
      input(type: "hidden", name: "event[reminders_submitted]", value: "1")
      legend(class: "label") do
        render Components::Icon.new("fa-bell", style: :regular)
        whitespace
        plain t("reminders.form.label")
      end
      p(class: "help") { t("reminders.form.help") }
      unconfirmed if @mail == :unconfirmed

      render Components::NestedFields.new(rows_class: "reminder-fields__rows", row_class: "reminder-fields__row", prefix: ->(index) { "event[reminders][#{index}]" },
                                          add_label: t("reminders.form.add"), remove_label: t("reminders.form.remove"), saved_whole: true, danger: false) do |fields|
        fields.rows { @reminders.each_with_index { |reminder, index| render_row(fields, *reminder.amount_and_unit, reminder.by_email?, index: index) } }
        fields.template { render_row(fields, 1, "days", false, index: Components::NestedFields::NEW_ROW) }
      end
    end
  end

  private

  def render_row(fields, amount, unit, by_email, index:)
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
      by_email_box(prefix, by_email) if @mail == :available
    end
  end

  # The box sends "1" over the "0" before it, so a row drawn with it always says.
  def by_email_box(prefix, checked)
    input(type: "hidden", name: "#{prefix}[by_email]", value: "0")
    label(class: "checkbox reminder-fields__email") do
      input(type: "checkbox", name: "#{prefix}[by_email]", value: "1", checked: checked)
      whitespace
      plain t("reminders.form.by_email")
    end
  end

  def unconfirmed
    p(class: "help") do
      plain t("reminders.form.email_unconfirmed")
      whitespace
      a(href: account_path) { t("reminders.form.confirm_address") }
    end
  end
end
