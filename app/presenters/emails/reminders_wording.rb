# frozen_string_literal: true

module Emails
  # Reminders that fell due together (RemindersMailer): one in a sentence,
  # several in a list, each by what its kind lets a mail say of it
  # (Event#reminder_mail_thing) and when it is due, on the person's clock.
  # The subject says only that it is a reminder, as a locked phone shows it.
  class RemindersWording < Wording
    # reminders: Reminders::StillDue's, soonest due first. calendar_url: where
    # they are seen in the app; unsubscribe_url: the link that stops them all.
    def initialize(profile, reminders:, calendar_url:, unsubscribe_url:)
      super(profile)
      @reminders = reminders
      @calendar_url = calendar_url
      @unsubscribe_url = unsubscribe_url
    end

    def subject = I18n.t("emails.reminders.subject", count: count)

    def paragraphs = [ one? ? said(@reminders.first, :one) : I18n.t("emails.reminders.several") ]

    def items = one? ? [] : @reminders.map { said(_1, :item).upcase_first }

    def action = Action.new(label: I18n.t("emails.reminders.action", count: count), url: @calendar_url)

    def closing = I18n.t("emails.reminders.closing", count: count)

    def unsubscribe = Action.new(label: I18n.t("emails.reminders.unsubscribe"), url: @unsubscribe_url)

    private

    def count = @reminders.size
    def one? = count == 1

    # "your task “Water the plants” at 14:30 on Friday 31 October", worded
    # as a sentence (:one) or a line of a list (:item).
    def said(reminder, form)
      I18n.t("emails.reminders.#{form}.#{reminder.timed ? "timed" : "untimed"}",
             thing: reminder.occurrence.event.reminder_mail_thing(reminder.occurrence),
             day: I18n.l(reminder.due_at, format: I18n.t("reminders.formats.mail_day")),
             time: I18n.l(reminder.due_at, format: I18n.t("reminders.formats.mail_time")))
    end
  end
end
