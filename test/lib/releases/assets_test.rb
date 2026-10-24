# frozen_string_literal: true

require "test_helper"

class Releases::AssetsTest < ActiveSupport::TestCase
  include ReleaseRepositories

  IMAGE = "ghcr.io/owner/household:2026.11.1@sha256:#{"a" * 64}"

  test "compose.yml is pinned to the release's image, and the installer comes as the commit has it" do
    with_repository do |repo|
      repo.commit("Start", "compose.yml" => "services:\n  web:\n    image: ${HOUSEHOLD_IMAGE}\n  job:\n    image: ${HOUSEHOLD_IMAGE}\n",
                           "install.sh" => "#!/bin/sh\necho hello\n")
      assets = assets_for(repo)

      assert_equal [ "release.json", "compose.yml", "install.sh", "SHA256SUMS" ], assets.files.keys
      assert_equal "services:\n  web:\n    image: #{IMAGE}\n  job:\n    image: #{IMAGE}\n", assets.files["compose.yml"]
      assert_equal "#!/bin/sh\necho hello\n", assets.files["install.sh"]
      assert_empty assets.missing
    end
  end

  test "SHA256SUMS holds every other file's checksum, as sha256sum -c reads it" do
    with_repository do |repo|
      repo.commit("Start", "compose.yml" => "image: ${HOUSEHOLD_IMAGE}\n", "install.sh" => "#!/bin/sh\n")
      files = assets_for(repo).files

      sums = files["SHA256SUMS"].lines.to_h { _1.chomp.split("  ").reverse }
      assert_equal [ "compose.yml", "install.sh", "release.json" ], sums.keys
      sums.each { |name, sum| assert_equal Digest::SHA256.hexdigest(files.fetch(name)), sum, name }
    end
  end

  test "release.json says what the release is" do
    with_repository do |repo|
      repo.commit("Start")
      repo.tag("v2026.10.2")
      repo.merge_pull_request(5, "Rebuild", "db/migrate/20261102000000_rebuild.rb" => "safety_assured { rename_table :a, :b }")
      manifest = JSON.parse(assets_for(repo, downtime_seconds: 41).files["release.json"])

      assert_equal({ "version" => "2026.11.1", "tag" => "v2026.11.1", "commit" => repo.head, "image" => IMAGE, "previous" => "2026.10.2",
                     "stopped_migrations" => [ "db/migrate/20261102000000_rebuild.rb" ], "downtime_seconds" => 41 }, manifest)
    end
  end

  test "a commit whose compose.yml names no placeholder, or that has no installer, releases without them and says so" do
    with_repository do |repo|
      repo.commit("Start", "compose.yml" => "services:\n  web:\n    build: .\n")
      assets = assets_for(repo)

      assert_equal [ "release.json", "SHA256SUMS" ], assets.files.keys
      assert_equal 2, assets.missing.size
      assert_match "compose.yml names no ${HOUSEHOLD_IMAGE}", assets.missing.first
    end
  end

  private

  def assets_for(repo, downtime_seconds: nil)
    repository = Releases::Repository.new(repo.root)
    plan = Releases::Plan.new(repository, "HEAD", on: Date.new(2026, 11, 3))
    Releases::Assets.new(repository, plan, image: IMAGE, downtime_seconds: downtime_seconds)
  end
end
