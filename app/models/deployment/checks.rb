# frozen_string_literal: true

module Deployment
  # What this copy finds when it looks at itself: whether its database
  # answers, and whether a job worker has been heard from lately (nil where
  # jobs don't go through Solid Queue, as in tests).
  Checks = Data.define(:database, :worker) do
    def self.run = new(database: Deployment.database_ok?, worker: Deployment.worker_alive?)

    # How lately a worker must have been heard from to count as alive.
    def worker_window = Lexicon::Worker::FRESH
  end
end
