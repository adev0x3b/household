# frozen_string_literal: true

# Something a profile should hear about without having watched it happen:
# what someone else did with their things (a share) or their account (a
# link to set its password, their reminders stopped from a mail), how a
# long job they started ended (an import, an eval), or something of theirs
# coming due (a reminder they set, Reminders::DispatchJob). Created and
# pushed live by Notifications::Deliver, listed under the navbar's bell.
#
# `subject` is what it's about (a Recipe, a LexiconImport…); `subject_title`
# keeps its name as it was, so the line still reads right after the subject
# is renamed, unshared or deleted. `data` holds what the kind's wording needs
# ("language", "passed"/"total", a "detail" line, an eval's "run_id"). The
# words themselves are Notifications::Wording's.
#
# A message (message_received) is one notification per conversation: the
# next message refreshes it (Notifications::Deliver's `replace:`) instead of
# lining up under the bell, like a phone's messaging apps do.
#
# Some are for the admin alone, about what only they can fix: a new
# kind of error, a job that failed for good (Admins::Alert).
#
# Some ask for an answer: a link to accept or decline, a change to one's
# item to approve or decline. Their buttons sit on the row while the
# question is open (Notifications::Destination#actions).
class Notification < ApplicationRecord
  SUBJECT_TYPES = %w[Event Recipe GroceryList Collection Book Bookshelf Upload Conversation LexiconImport LexiconLanguage Link LinkApproval].freeze

  # How it ended; the others are plain news.
  FAILURES = %w[import_failed lexicon_eval_failed eval_cases_failed approval_failed deploy_failed release_undone upload_failed
                error_reported job_failed].freeze
  SUCCESSES = %w[import_finished lexicon_eval_passed eval_cases_written link_accepted approval_approved deploy_succeeded release_finished].freeze
  # How the admin's press on the delivery console ended, a release with
  # downtime, told to everyone, and a newer release a self-hosted copy's
  # admins can update to: they lead to the console.
  DEPLOYMENT_KINDS = %w[deploy_succeeded deploy_failed release_starting release_finished release_undone release_available].freeze
  # What went wrong in the app itself: they lead to the admin's pages of
  # errors and jobs.
  ADMIN_ALERTS = %w[error_reported job_failed].freeze

  belongs_to :profile
  belongs_to :actor, class_name: "Profile", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  enum :kind, {
    shared: 0, unshared: 1,
    import_finished: 10, import_failed: 11, import_needs_review: 12, import_unchanged: 13,
    lexicon_eval_passed: 20, lexicon_eval_failed: 21,
    eval_cases_written: 30, eval_cases_failed: 31,
    eval_run_finished: 40,
    reminder_due: 50, reminder_mails_stopped: 51,
    message_received: 60,
    link_requested: 70, link_accepted: 71, link_declined: 72, link_removed: 73, link_permissions_changed: 74,
    approval_requested: 75, approval_approved: 76, approval_declined: 77, approval_failed: 78,
    deploy_succeeded: 80, deploy_failed: 81, release_starting: 82, release_finished: 83, release_undone: 84, release_available: 85,
    upload_ready: 90, upload_failed: 91,
    password_link_made: 100,
    error_reported: 110, job_failed: 111
  }, validate: true

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  # Those after `notification` in recent_first's order.
  scope :older_than, ->(notification) { where("(notifications.created_at, notifications.id) < (?, ?)", notification.created_at, notification.id) }

  def unread? = read_at.nil?

  def mark_read!
    update!(read_at: Time.current) if unread?
  end

  # How it ended, for a toast's color.
  def failure? = FAILURES.include?(kind)
  def success? = SUCCESSES.include?(kind)

  def about_deployment? = DEPLOYMENT_KINDS.include?(kind)
  def admin_alert? = ADMIN_ALERTS.include?(kind)

  # Whether its push may wake a phone: something due, something that
  # failed, a deploy that went through, a link that opens one's account.
  # The rest waits for the phone.
  def urgent? = reminder_due? || failure? || deploy_succeeded? || password_link_made?
end
