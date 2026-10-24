# frozen_string_literal: true

# A deploy migrates while the previous version still serves
# (docs/architecture/delivery.md, "A deploy without a gap"), so a migration
# must leave the database usable by both: add a column, use it, remove it in
# a later deploy. strong_migrations refuses the
# operations that break that (removing or renaming a column or table, changing
# a type, a blocking index…) when the migration runs: in development, in CI
# (which migrates the branch on top of the base branch's schema) and in
# production's boot. A deliberate exception goes in `safety_assured { }` and is
# released with the app stopped, unless a `# zero-downtime:` line says why it
# runs beside the previous version.

# The migrations already on main when this started are history.
StrongMigrations.start_after = 2026_10_10_090000

# The Postgres every installation and CI run (test/lib/toolchain_versions_test.rb
# keeps their images on this major).
StrongMigrations.target_version = 16

# A migration waits at most this long for a lock, so it can't queue every
# request behind it; it's retried a few times before the deploy fails.
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.lock_timeout_retries = 3
StrongMigrations.statement_timeout = 1.hour

# Fresh statistics after an index is added.
StrongMigrations.auto_analyze = true
