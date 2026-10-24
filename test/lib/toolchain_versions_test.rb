# frozen_string_literal: true

require "test_helper"

# The same Ruby and the same Postgres are named in several files that nothing
# else ties together: development, CI, the image and every installation have
# to agree, or a change passes in one and fails in another.
class ToolchainVersionsTest < ActiveSupport::TestCase
  POSTGRES_FILES = %w[ compose*.yml config/deploy*.yml .github/workflows/*.yml ].freeze

  test "the image runs the Ruby that .ruby-version names, on a named Debian release" do
    dockerfile = Rails.root.join("Dockerfile").read
    ruby = Rails.root.join(".ruby-version").read.strip.delete_prefix("ruby-")

    assert_equal ruby, dockerfile[/^ARG RUBY_VERSION=(\S+)$/, 1]
    assert_match(/^FROM \S+:\$RUBY_VERSION-slim-[a-z]+ AS base$/, dockerfile)
  end

  test "every Postgres the app runs on is the major strong_migrations checks against" do
    files = POSTGRES_FILES.flat_map { Dir.glob(Rails.root.join(_1)) }.map { Pathname.new(_1) }
    images = files.to_h { [ _1.relative_path_from(Rails.root).to_s, _1.read.scan(/\bimage: postgres:(\d+)/).flatten ] }
    images = images.reject { |_, majors| majors.empty? }

    assert_includes images.keys, "config/deploy.yml"
    assert_includes images.keys, ".github/workflows/ci.yml"
    assert_includes images.keys, "compose.dev.yml"
    images.each do |path, majors|
      assert_equal [ StrongMigrations.target_version.to_s ], majors.uniq, path
    end
  end
end
