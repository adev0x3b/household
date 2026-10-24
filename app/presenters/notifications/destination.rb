# frozen_string_literal: true

# Where a notification leads (its row's link, a push notification's tap)
# and what its row asks there: the routes of the UI, kept out of the model.
# Nowhere once its subject is gone or no longer the reader's; no buttons
# once what it asks is answered.
#
#   destination = Notifications::Destination.new(notification)
#   destination.path      # => "/recipes/12", or nil
#   destination.actions   # => [Action(:approve, path, :post), Action(:decline, path, :delete)]
class Notifications::Destination
  include Rails.application.routes.url_helpers
  include Rails.application.routes.mounted_helpers

  # A button on the row: what it is called, where it goes and how.
  Action = Data.define(:name, :path, :verb)

  def initialize(notification)
    @notification = notification
  end

  # The subject's own page (a recipe's, a file's) or, for a thing that has
  # no page of its own, where it is seen (a series on the calendar, a shelf
  # among the bookshelves, a link on the links page: config/routes.rb says
  # which). A reminder opens its day; the admin's news opens the console,
  # their alerts the errors or the failed jobs, and an eval's its run, which
  # depend on the notification, not a subject; a file given up on opens the
  # Files section, to upload it again. A password link opens nothing: what
  # to do about it is in its words.
  def path
    return if @notification.unshared? || @notification.password_link_made?
    return console_path if @notification.about_deployment?
    return alert_path if @notification.admin_alert?
    return reminded_day_path if @notification.reminder_due?
    return uploads_path if @notification.upload_failed?
    return eval_run_path if subject.nil?

    polymorphic_path(subject)
  end

  # A request the reader is the one to answer, while it is still open: the
  # subject's policy says whether they are, as the reader.
  def actions
    if @notification.approval_requested? && subject&.live? && policy.approve?
      [ Action.new(:approve, link_approval_consent_path(subject), :post), Action.new(:decline, link_approval_path(subject), :delete) ]
    elsif @notification.link_requested? && subject && policy.accept?
      [ Action.new(:accept, link_acceptance_path(subject), :post), Action.new(:decline, link_path(subject), :delete) ]
    else
      []
    end
  end

  private

  def subject = @notification.subject
  def data = @notification.data

  def policy = Pundit.policy!(@notification.profile, subject)

  def console_path = (admin_deployment_path if @notification.profile.admin?)

  # The whole list rather than the one error or job: more may have come in
  # the hour the alert stood for.
  def alert_path
    return unless @notification.profile.admin?

    @notification.job_failed? ? admin_jobs.jobs_path(status: :failed) : admin_errors_path
  end

  # The calendar's month, at the day the reminder is about.
  def reminded_day_path
    return if subject.nil?
    return polymorphic_path(subject) if data["date"].blank?

    date = Date.parse(data["date"])
    calendar_path(month: date.month, year: date.year, anchor: "day_#{date.iso8601}")
  end

  def eval_run_path = (assistant_evals_run_path(data["run_id"]) if data["run_id"].present?)
end
