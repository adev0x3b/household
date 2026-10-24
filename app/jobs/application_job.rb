# frozen_string_literal: true

# One policy for every job; a job adds only what is its own (PushJob's push
# service errors).
class ApplicationJob < ActiveJob::Base
  # What passes — a deadlock, a lock that waited too long, a lost connection
  # — is tried again, a little later each time.
  TRANSIENT = [ ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::ConnectionNotEstablished,
                ActiveRecord::ConnectionFailed ].freeze
  retry_on(*TRANSIENT, wait: :polynomially_longer, attempts: 5)

  # A record gone between enqueuing and running (deleted meanwhile): nothing
  # left to do.
  discard_on ActiveJob::DeserializationError

  after_discard { |_job, error| alert_admins(error) }

  # A job whose work can't be done twice — a model's reply, the hand-off to
  # one, a long import started by a person — fails on those errors instead,
  # recorded, for whoever started it to press again.
  def self.runs_once = retry_on(*TRANSIENT, attempts: 1)

  # For jobs that run for minutes (a lexicon import, an eval run): Solid Queue
  # in every environment, worked by its own process (bin/jobs). Development's
  # default adapter runs jobs inside the web server, where a long one holds
  # Rails' code-loading lock: after any file change every page waits for it
  # until the job ends. Tests keep their test adapter.
  def self.runs_outside_web_server
    self.queue_adapter = :solid_queue unless Rails.env.test?
  end

  private

  # A job that failed for good is one only the admin can redo
  # (/admin/jobs). A job let go on purpose, its record gone, is not.
  def alert_admins(error)
    return if error.is_a?(ActiveJob::DeserializationError) || !alerts_admins_when_failing?

    Admins::Alert.call(:job_failed, name: self.class.name, detail: "#{error.class}: #{error.message}")
  end

  def alerts_admins_when_failing? = true

  # One item of many (a series' reminders, an abandoned upload) that fails
  # is reported and passed over, so it doesn't keep the rest from being
  # done, run after run. What passes (TRANSIENT) still fails the job, to be
  # tried again whole.
  def on_its_own(item)
    yield
  rescue *TRANSIENT
    raise
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { job: self.class.name, item: item.to_global_id.to_s })
  end

  # Tells whoever started a long job how it ended (their navbar bell, a live
  # toast): profile_id travels in the job's arguments, nil when nobody asked
  # (a rake task). Never fails the job.
  def notify(profile_id, kind, subject: nil, **data)
    recipient = profile_id && Profile.find_by(id: profile_id) or return
    Notifications::Deliver.call(recipient: recipient, kind: kind, subject: subject, data: data)
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { job: self.class.name, profile_id: profile_id, kind: kind })
  end
end
