# frozen_string_literal: true

# Whether a job worker is there to run imports (Solid Queue's `bin/jobs`,
# Procfile.dev in development): one that beat its heart lately. nil where
# the jobs don't go to Solid Queue (tests).
module Lexicon
  module Worker
    FRESH = 2.minutes

    module_function

    def alive?
      return unless Lexicon::ImportJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

      SolidQueue::Process.where(kind: "Worker").where(last_heartbeat_at: FRESH.ago..).exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end
  end
end
