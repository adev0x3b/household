# frozen_string_literal: true

# One import of a language's nouns from Wiktionary (Lexicon::Import): where
# it came from, how far it got, and its report — the steps with ✓/✗ and
# every check's result. Only one import per language is active; its rows are
# the ones Lexicon::Matcher reads.
#
# It also knows the job working it (job_id) and whether someone asked it to
# stop (cancel_requested_at), so the admin page can tell an import that's
# queued, running, or whose job is gone — and cancel it.
class LexiconImport < ApplicationRecord
  # awaiting_review: loaded and checked, waiting for a person to confirm the
  # language's test cases (Lexicon::DictionaryCheck::NeedsReview) — its rows
  # are kept, and Continue resumes it at the dictionary step.
  # cancelled: stopped on request (Lexicon::Import::Cancelled), its rows deleted.
  enum :status, { running: 0, failed: 1, active: 2, superseded: 3, unchanged: 4, awaiting_review: 5, cancelled: 6 }

  # An import whose job can't be seen (another adapter) stops counting as
  # running after this long without a word from it.
  QUIET = 10.minutes

  # A step is under way while it runs or waits; with the ones still pending
  # it is what a cancel leaves undone.
  UNDER_WAY_STEPS = %w[running waiting].freeze
  UNFINISHED_STEPS = [ "pending", *UNDER_WAY_STEPS ].freeze

  has_many :lexicon_lemmas, dependent: :delete_all

  validates :language, presence: true

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def self.active_for(language) = active.find_by(language: language.to_s)

  # The active import id of every language that has one: { "it" => 3, "en" => 4 }.
  def self.active_ids = active.pluck(:language, :id).to_h

  # A running import of the language that's really going (its job queued or
  # working) — what keeps a second one from starting.
  def self.live_for(language) = running.where(language: language.to_s).latest_first.find(&:live?)

  def steps = Array(report["steps"])
  def checks = Array(report["checks"])
  def counts = report.fetch("counts", {})
  def finished? = !running?

  # Queues its Lexicon::ImportJob; if that fails (no queue, a database error)
  # the import fails at once, saying so, instead of waiting for a job that
  # will never come. Returns whether it was queued.
  # fail_on_error: false keeps the import as it is (Continue on one waiting
  # for review); the reason is then in enqueue_failure.
  def enqueue!(fail_on_error: true, **args)
    job = Lexicon::ImportJob.perform_later(id, **args)
    raise(job.enqueue_error || ActiveJob::EnqueueError.new("not queued")) unless job.successfully_enqueued?

    update_columns(job_id: job.job_id, updated_at: Time.current)
    true
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { lexicon_import_id: id, step: "enqueue" })
    @enqueue_failure = "its job couldn't be queued (#{e.class.name.demodulize}: #{e.message.squish.truncate(200)}) — is the job worker set up?"
    update!(status: :failed, failed_step: "configure", finished_at: Time.current, error: @enqueue_failure) if fail_on_error
    false
  end

  attr_reader :enqueue_failure

  # Where its job is: :queued, :working, :finished, :failed, :missing (never
  # queued, or gone), or :unknown when the job isn't one Solid Queue keeps.
  def job_state
    return :missing if job_id.blank? && created_at < 1.minute.ago
    return :unknown unless job_id.present? && solid_queue?

    job = SolidQueue::Job.find_by(active_job_id: job_id)
    return :missing if job.nil?

    { finished: :finished, claimed: :working, ready: :queued, scheduled: :queued, blocked: :queued, failed: :failed }
      .fetch(job.status&.to_sym, :queued)
  rescue ActiveRecord::ActiveRecordError
    :unknown
  end

  # Running and really going: its job queued or working (or, where that
  # can't be seen, heard from in the last QUIET).
  def live?
    return false unless running?

    case job_state
    when :queued, :working then true
    when :unknown then updated_at > QUIET.ago
    else false
    end
  end

  # Asked to stop, as written in the database now (the job and the page are different processes).
  def cancel_requested? = self.class.where(id: id).where.not(cancel_requested_at: nil).exists?

  # Stops it. A job working on it is asked to (it stops within seconds, its
  # eval process too): :stopping. One that never started, whose job is gone,
  # or that waits for review stops now — its job dropped, its rows deleted:
  # :cancelled. Anything else has nothing to stop: :finished.
  def cancel!
    return :finished unless running? || awaiting_review?

    if running? && (job_state == :working || (job_state == :unknown && live?))
      update!(cancel_requested_at: Time.current)
      return :stopping
    end
    discard_job!
    cancelled_now!
    :cancelled
  end

  # The queued job of an import cancelled before it started, dropped.
  def discard_job!
    return unless job_id.present? && solid_queue?

    SolidQueue::Job.find_by(active_job_id: job_id)&.discard
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  private

  def cancelled_now!
    current = steps.find { UNDER_WAY_STEPS.include?(_1["status"]) }
    report["steps"] = steps.map do |step|
      if step.equal?(current) then step.merge("status" => "cancelled", "detail" => "cancelled on request")
      elsif UNFINISHED_STEPS.include?(step["status"]) then step.merge("status" => "skipped").except("detail")
      else step
      end
    end
    transaction do
      lexicon_lemmas.delete_all
      update!(status: :cancelled, failed_step: current&.dig("name"), error: "cancelled on request", finished_at: Time.current,
              cancel_requested_at: Time.current)
    end
  end

  def solid_queue? = Lexicon::ImportJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
end
