# frozen_string_literal: true

module Delivery
  # One destination as the console shows it. Each answer is read from
  # GitHub once, and only when a card asks for it.
  class Environment
    # How many recent deployments to look through for the last success.
    LOOKBACK = 10

    attr_reader :name

    def initialize(name)
      @name = name.to_s
    end

    def production? = name == "production"
    def staging? = name == "staging"
    def demo? = name == "demo"
    def dev? = name == "dev"
    # Fed from main (staging, the demo, production), as opposed to running a branch (dev).
    def mainline? = Deployment::MAINLINE.include?(name)
    def here? = Deployment.destination == name
    def url = Deployment.url(name)

    # The newest deployment that succeeded: what runs there, or ran until
    # it was stopped (dev only: a preview starts it again). A rehearsal
    # counts, since staging keeps running the rehearsed version. Nil where
    # nothing was ever recorded.
    def record
      return @record if defined?(@record)

      @record = records.find(&:succeeded?)
    end

    def stopped? = record&.task == "stop"
    def running? = record.present? && !stopped?
    # The newest attempt of any outcome (a failed deploy, a held one, one in progress).
    def last = records.first

    def version = record&.sha
    def short_version = version&.first(7)
    def deployed_at = record&.finished_at || record&.created_at
    def deployed_by = record&.requested_by
    def rolled_back? = record&.task == "rollback"

    def health = (@health ||= Deployment::Health.of(name))

    # The newest rehearsal of a version that ended (staging only): passed or undone.
    def rehearsal(sha)
      return if sha.blank? || !staging?

      Github.records(environment: name, task: "rehearse", sha: sha, limit: 3).find { !_1.live? }
    end

    # The branch dev runs, and whether its preview started from fresh data:
    # the newest preview that succeeded, as long as it is still what runs
    # (a restart in between keeps the version, so it still is).
    def branch = preview&.branch
    def fresh? = preview&.fresh? || false

    private

    def records = (@records ||= Github.records(environment: name, limit: LOOKBACK))

    def preview
      return unless dev? && version

      found = records.find { _1.task == "preview" && _1.succeeded? }
      found if found&.sha == version
    end
  end
end
