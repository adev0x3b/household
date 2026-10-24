# frozen_string_literal: true

module Deployment
  # What the daily check last found about the release this copy runs
  # (Deployment::CheckForUpdate): the newest release, and when it asked.
  # Kept in Solid Cache, since an answer lost is only asked again at the
  # next check, and one older than a few days is no longer trusted.
  class Update
    KEY = "deployment/update"
    KEPT = 3.days

    attr_reader :running, :newest, :checked_at

    def self.remember(newest)
      Rails.cache.write(KEY, { "version" => newest&.version, "checked_at" => Time.current }, expires_in: KEPT)
    end

    # The last answer for the release running, else nil (never asked).
    def self.for(running)
      found = Rails.cache.read(KEY)
      return unless running && found

      newest = found["version"] && Release.new(repository: running.repository, version: found["version"])
      new(running: running, newest: newest, checked_at: found["checked_at"])
    end

    def initialize(running:, newest:, checked_at:)
      @running = running
      @newest = newest
      @checked_at = checked_at
    end

    def available? = newest.present? && newest.newer_than?(running)
  end
end
