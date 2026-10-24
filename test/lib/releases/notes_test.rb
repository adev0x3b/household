# frozen_string_literal: true

require "test_helper"

class Releases::NotesTest < ActiveSupport::TestCase
  include ReleaseRepositories

  IMAGE = "ghcr.io/owner/household:2026.11.1@sha256:#{"a" * 64}"

  test "the first release says so, and names its image" do
    with_repository do |repo|
      repo.commit("Start")

      assert_equal "## The first release\n\nThe image: `#{IMAGE}`\n", notes_for(repo)
    end
  end

  test "an update that stops the app says so first, with production's downtime, then lists what changed" do
    with_repository do |repo|
      repo.commit("Start")
      repo.tag("v2026.10.2")
      repo.merge_pull_request(5, "Rebuild the core", "db/migrate/20261102000000_rebuild.rb" => "safety_assured { rename_table :a }")

      assert_equal <<~MARKDOWN, notes_for(repo, downtime_seconds: 41)
        **This update stops the app while it changes the database.** Production was behind its maintenance page for 41 seconds. The migrations that need it: `db/migrate/20261102000000_rebuild.rb`.

        ## What's new since 2026.10.2

        - Rebuild the core (#5)

        The image: `#{IMAGE}`
      MARKDOWN
    end
  end

  private

  def notes_for(repo, downtime_seconds: nil)
    plan = Releases::Plan.new(Releases::Repository.new(repo.root), "HEAD", on: Date.new(2026, 11, 3))
    Releases::Notes.new(plan, image: IMAGE, downtime_seconds: downtime_seconds).to_s
  end
end
