# frozen_string_literal: true

require "test_helper"

# Delivery::Github::Canned stands in for GitHub where there is no token: a
# development server or the dev destination asking for it. Its made-up
# pipeline must be whole enough for the console to show every card and
# offer every action, and a press through it must change nothing.
class Delivery::Github::CannedTest < ActiveSupport::TestCase
  Canned = Delivery::Github::Canned

  isolate_env "DEPLOY_GITHUB_CANNED", "KAMAL_DESTINATION", "DEPLOY_DISPATCH_TOKEN"

  test "it stands in on dev or in development when asked, and nowhere else" do
    assert_not Canned.on?, "nothing asked for it"

    ENV["DEPLOY_GITHUB_CANNED"] = "1"
    assert_not Canned.on?, "the test environment, on no destination"
    ENV["KAMAL_DESTINATION"] = "dev"
    assert_predicate Canned, :on?
    ENV["KAMAL_DESTINATION"] = "production"
    assert_not Canned.on?, "never on a real destination"
  end

  test "its pipeline is whole: main's head passed CI and runs on the mainline, dev runs a branch ready to merge" do
    ENV["DEPLOY_GITHUB_CANNED"] = "1"
    ENV["KAMAL_DESTINATION"] = "dev"
    pipeline = Delivery::Pipeline.new

    assert_equal Canned::HEAD, pipeline.head.sha
    assert_equal [ :passed, true ], [ pipeline.ci_state, pipeline.image_built? ]
    pipeline.mainline.each do |environment|
      assert_equal [ Canned::HEAD, :head ], [ environment.version, pipeline.sync(environment) ], environment.name
      assert_predicate environment, :running?
    end
    assert_equal [ Canned::BRANCH_HEAD, Canned::BRANCH, true ], [ pipeline.dev.version, pipeline.dev.branch, pipeline.dev.fresh? ]
    assert_equal [ :head, :ready ], [ pipeline.sync(pipeline.dev), pipeline.merge_state(pipeline.dev) ]
    assert_equal [ "Try the console on dev" ], pipeline.merge_pending(pipeline.dev).map(&:title)
    assert_empty pipeline.held(pipeline.production)
    assert_not pipeline.frozen?
    assert_equal 1, pipeline.deploy_runs.size
    assert_not_predicate pipeline, :live?
    assert_nil pipeline.staging.rehearsal(Canned::HEAD)
    assert_equal %i[frequency lead_time failure_rate recovery_time], Delivery::Metrics.for_production.all.keys
  end

  test "frozen when the variable says so, with a note" do
    ENV["DEPLOY_GITHUB_CANNED"] = "frozen"
    ENV["KAMAL_DESTINATION"] = "dev"
    pipeline = Delivery::Pipeline.new

    assert_predicate pipeline, :frozen?
    assert_match(/alex · .* · trying the freeze/, pipeline.freeze_note)
  end

  test "every write answers 204 and changes nothing, a merge answers main's head, the unknown is 404" do
    ENV["DEPLOY_GITHUB_CANNED"] = "1"
    ENV["KAMAL_DESTINATION"] = "dev"

    Delivery::Github.dispatch(action: "deploy", reason: "trying", destination: "staging")
    assert_equal Canned::HEAD, Delivery::Github.merge_pull_request(Canned::PULL, head_sha: Canned::BRANCH_HEAD, branch: Canned::BRANCH)
    assert_predicate Delivery::Pipeline.new.dev, :running?, "nothing changed"
    assert_equal "404", answer("/nothing").code
  end

  test "whatever the console asks about beyond the cards is answered in kind" do
    older = "b2" * 20

    assert_equal "An earlier change", title(answer("/commits/#{older}")), "any sha has a commit, so a rollback's candidates have titles"
    assert_equal [ Canned::BRANCH, "main" ], JSON.parse(answer("/branches").body).pluck("name"), "the branches a preview offers"
    assert_empty JSON.parse(answer("/pulls", head: "example:another-branch").body), "only the branch on dev has a pull request"
    assert_equal "diverged", JSON.parse(answer("/compare/#{Canned::BRANCH_HEAD}...#{Canned::HEAD}").body)["status"]
    assert_equal "identical", JSON.parse(answer("/compare/#{older}...#{Canned::HEAD}").body)["status"]
    assert_equal Deployment::DESTINATIONS, JSON.parse(answer("/deployments").body).pluck("environment"), "every destination's, asked for all at once"
    assert_equal "404", answer("/actions/variables/#{Delivery::Github::FREEZE_NOTE}").code, "no note while nothing is frozen"
  end

  private

  def answer(path, **query)
    uri = URI("https://api.github.com/repos/example/household#{path}")
    uri.query = query.to_query if query.any?
    Canned.perform(Net::HTTP::Get.new(uri))
  end

  def title(response) = JSON.parse(response.body).dig("commit", "message")
end
