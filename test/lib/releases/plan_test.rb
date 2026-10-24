# frozen_string_literal: true

require "test_helper"

class Releases::PlanTest < ActiveSupport::TestCase
  include ReleaseRepositories

  NOVEMBER = Date.new(2026, 11, 3)
  HELD = "safety_assured { rename_table :a, :b }"
  MARKED = "# zero-downtime: ignored since the last deploy\nsafety_assured { remove_column :a, :c }"

  test "the first release is the month's first, with nothing before it" do
    with_repository do |repo|
      repo.commit("Start")
      plan = plan_for(repo, "HEAD")

      assert_nil plan.reason_to_skip
      assert_equal "2026.11.1", plan.version.to_s
      assert_nil plan.previous
      assert_empty plan.changes
      assert_empty plan.stopped_migrations
    end
  end

  test "a later release names the one before and lists what main gained since, oldest first" do
    with_repository do |repo|
      repo.commit("Start")
      repo.tag("v2026.10.4")
      repo.merge_pull_request(12, "Show the bell's count")
      repo.commit("Fix a typo by hand")
      repo.merge_pull_request(13, "Keep the toast")
      plan = plan_for(repo, "HEAD")

      assert_equal "2026.11.1", plan.version.to_s
      assert_equal "v2026.10.4", plan.previous.tag
      by_hand = repo.git("rev-parse", "--short", "HEAD~1").strip
      expected = [ [ "Show the bell's count", "#12" ], [ "Fix a typo by hand", by_hand ], [ "Keep the toast", "#13" ] ]
      assert_equal expected, (plan.changes.map { [ _1.title, _1.reference ] })
    end
  end

  test "tags that aren't a release's are ignored" do
    with_repository do |repo|
      repo.commit("Start")
      repo.tag("deployed-somewhere")
      repo.tag("v2026.11")

      assert_nil plan_for(repo, "HEAD").previous
    end
  end

  test "a migration that needs the app stopped is named; one marked zero-downtime, or one from before, isn't" do
    with_repository do |repo|
      repo.commit("Start", "db/migrate/20261001000000_old.rb" => "safety_assured { remove_column :a, :b }")
      repo.tag("v2026.10.1")
      repo.merge_pull_request(20, "Rebuild the core", "db/migrate/20261102000000_rebuild.rb" => HELD)
      repo.merge_pull_request(21, "Drop a column", "db/migrate/20261103000000_drop.rb" => MARKED)

      assert_equal [ "db/migrate/20261102000000_rebuild.rb" ], plan_for(repo, "HEAD").stopped_migrations
    end
  end

  test "a commit released already, or one before the last release, makes none" do
    with_repository do |repo|
      first = repo.commit("Start")
      second = repo.merge_pull_request(1, "Something")
      repo.tag("v2026.11.1")

      assert_equal "#{second[0, 7]} is v2026.11.1 already.", plan_for(repo, second).reason_to_skip
      assert_match "doesn't come after v2026.11.1", plan_for(repo, first).reason_to_skip
    end
  end

  test "a commit the checkout doesn't have is an error" do
    with_repository do |repo|
      repo.commit("Start")

      error = assert_raises(Releases::Error) { plan_for(repo, "0" * 40) }
      assert_match "no commit", error.message
    end
  end

  private

  def plan_for(repo, commit) = Releases::Plan.new(Releases::Repository.new(repo.root), commit, on: NOVEMBER)
end
