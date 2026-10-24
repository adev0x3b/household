# frozen_string_literal: true

module Notifications
  # Saves a notification, pushes it to the recipient's open pages and, as a
  # Web Push, to the devices they turned notifications on for (PushJob).
  #
  #   Notifications::Deliver.call(recipient: share.profile, kind: :shared, subject: recipe, actor: current_profile)
  #   Notifications::Deliver.call(recipient: starter, kind: :import_failed, subject: import, data: { language: "Italian", detail: import.error })
  #
  # `title` names the subject when its own name won't do (a reminder: the
  # occurrence's, not the series' first).
  #
  # `replace:` is an earlier, still unread notification about the same
  # thing (the messages of one conversation): it is brought up to date and
  # moved to the top instead of a second one being added.
  #
  # Nobody is notified of what they did themselves (a job's end has no
  # actor: whoever started it is told). The open pages and the devices hear
  # of it once it is saved: a caller's transaction that rolls back takes it
  # back unheard, and a push job never looks for a notification not yet
  # there. Returns the notification (nil when none was due).
  class Deliver
    DETAIL_LENGTH = 160

    def self.call(recipient:, kind:, subject: nil, actor: nil, data: {}, title: nil, replace: nil)
      return if recipient.nil? || recipient == actor

      data = data.to_h.stringify_keys.compact
      data["detail"] = data["detail"].to_s.squish.truncate(DETAIL_LENGTH) if data["detail"].present?
      attributes = { profile: recipient, actor: actor, kind: kind, data: data, subject: subject, subject_title: title.presence || title_of(subject) }
      notification = replace&.unread? ? replace.tap { _1.update!(**attributes, created_at: Time.current) } : Notification.create!(**attributes)
      ActiveRecord.after_all_transactions_commit do
        Broadcaster.delivered(notification)
        push(notification)
      end
      notification
    end

    # To every device the recipient turned notifications on for (one job each).
    def self.push(notification)
      return unless PushNotifications.enabled?

      notification.profile.push_subscriptions.find_each { PushJob.perform_later(notification, _1) }
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { notification_id: notification.id, step: "enqueue push" })
    end

    # What the subject is called where it is shared (an event: its label),
    # else its name; a subject with neither leaves the caller to say.
    def self.title_of(subject) = subject.try(:shared_name).presence || subject.try(:name)
    private_class_method :title_of, :push
  end
end
