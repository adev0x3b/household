# frozen_string_literal: true

module Releases
  # Whether the commit production now runs is a new release, and which one.
  # A release only ever moves forward from the one before it, so a version
  # promoted again, or an older one promoted to go back, makes none.
  class Plan
    attr_reader :commit, :on

    def initialize(repository, commit, on:)
      @commit = repository.commit(commit)
      @released = repository.releases
      @repository = repository
      @on = on
    end

    # Why this commit makes no release, or nil when it makes one.
    def reason_to_skip
      if (version = @released.key(commit))
        "#{commit[0, 7]} is #{version.tag} already."
      elsif previous && !@repository.ancestor?(previous_commit, commit)
        "#{commit[0, 7]} doesn't come after #{previous.tag} on main, so it makes no release."
      end
    end

    def version = Version.following(@released.keys, on: on)
    def previous = @released.keys.max
    def previous_commit = previous && @released.fetch(previous)

    # What main gained since the release before (Repository#changes).
    def changes
      return [] unless previous

      @repository.changes(previous_commit, commit)
    end

    # The migrations since the release before that need the app stopped
    # (HeldMigrations). A first install has nothing running beside it.
    def stopped_migrations
      return [] unless previous

      added = @repository.added(previous_commit, commit, under: "db/migrate")
      HeldMigrations.among(added) { @repository.file(commit, _1) }
    end
  end
end
