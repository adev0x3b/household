# frozen_string_literal: true

# The one rule for a migration that needs the app stopped. bin/held-migrations
# applies it to a checkout and Delivery::HeldMigrations to GitHub's copy, so
# the pipeline and the console can't disagree.
module HeldMigrations
  MIGRATION = %r{\Adb/migrate/[^/]+\.rb\z}
  SAFETY_ASSURED = /safety_assured/
  ZERO_DOWNTIME = /^\s*# zero-downtime:/

  module_function

  # A path the rule applies to.
  def migration?(path) = MIGRATION.match?(path.to_s)

  # A migration's source: does deploying it need the app stopped?
  def held?(source)
    source = source.to_s
    SAFETY_ASSURED.match?(source) && !ZERO_DOWNTIME.match?(source)
  end

  # The held ones among added files, given each one's source: [path, …].
  # `source_of` reads a path's source at the version being deployed.
  def among(added_paths, &source_of)
    added_paths.select { |path| migration?(path) && held?(yield(path)) }
  end
end
