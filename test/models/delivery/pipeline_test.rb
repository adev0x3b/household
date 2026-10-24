# frozen_string_literal: true

require "test_helper"

# Delivery::Pipeline, Environment and HeldMigrations over the GitHub the
# fixtures draw (GithubFixtures): main's head passed CI with its image
# built, staging runs it after a rehearsal that passed, production runs
# three commits behind and one of them needs the app stopped, a deploy of
# staging is in progress; dev runs the branch fix-the-bell on fresh data,
# and the branch moved on.
class Delivery::PipelineTest < ActiveSupport::TestCase
  include CannedPipeline

  isolate_env "DEPLOY_DISPATCH_TOKEN"
  setup { with_deploy_token }

  test "main's head, its CI and its image" do
    canned do
      pipeline = Delivery::Pipeline.new
      assert_equal GithubFixtures::HEAD, pipeline.head.sha
      assert_equal "Show a paused eval run as paused on the page that follows", pipeline.head.title
      assert_equal :passed, pipeline.ci_state
      assert_predicate pipeline, :image_built?
    end
  end

  test "a commit and a run's jobs are asked of GitHub once, however many cards name them" do
    canned do
      pipeline = Delivery::Pipeline.new
      asked = Hash.new(0)
      commit = Delivery::Github.method(:commit)
      run_jobs = Delivery::Github.method(:run_jobs)
      swapping(Delivery::Github, :commit, ->(ref) { asked[ref] += 1; commit.call(ref) }) do
        swapping(Delivery::Github, :run_jobs, ->(id) { asked[:jobs] += 1; run_jobs.call(id) }) do
          2.times { assert_equal pipeline.head.title, pipeline.commit(GithubFixtures::HEAD).title }
          2.times { assert_predicate pipeline.jobs(pipeline.ci), :any? }
          assert_predicate pipeline, :image_built?
        end
      end
      assert_equal({ Delivery::Pipeline::BRANCH => 1, GithubFixtures::HEAD => 1, jobs: 1 }, asked)
      assert_not pipeline.canned?, "the fixtures stand in for GitHub's answers, not the canned pipeline"
    end
  end

  test "what each destination runs, who put it there, and how it stands against main" do
    canned do
      pipeline = Delivery::Pipeline.new
      dev, staging, demo, production = pipeline.environments
      assert_equal [ staging, demo, production ], pipeline.mainline
      assert_predicate dev, :dev?
      assert_not dev.mainline?
      assert_predicate demo, :demo?
      assert_predicate demo, :mainline?
      assert_equal GithubFixtures::HEAD, demo.version, "the demo runs what staging took"
      assert_equal :head, pipeline.sync(demo)

      assert_equal GithubFixtures::HEAD, staging.version
      assert_equal :head, pipeline.sync(staging)
      assert_empty pipeline.pending(staging)
      assert_equal "rehearse", staging.record.task
      assert_equal Time.utc(2026, 10, 13, 8, 54), staging.deployed_at

      assert_equal GithubFixtures::PRODUCTION, production.version
      assert_equal "CI: Release a version that needs the app stopped with one click", production.deployed_by
      assert_equal :behind, pipeline.sync(production)
      assert_equal 3, pipeline.behind_by(production)
      assert_equal [ "Fold event shares into links", "Trim the bell's wording", "Show a paused eval run as paused on the page that follows" ], pipeline.pending(production).map(&:title)
      assert_not production.rolled_back?

      # The last attempt on production was held.
      assert_predicate production.last, :failed?
      assert_predicate production.last, :held?
      assert_equal GithubFixtures::HEAD, production.last.sha
    end
  end

  test "the held migrations between two versions, by the shared rule" do
    canned do
      pipeline = Delivery::Pipeline.new
      assert_equal [ GithubFixtures::HELD_MIGRATION ], pipeline.held(pipeline.production)
      assert_equal [ GithubFixtures::HELD_MIGRATION ], pipeline.held_between(GithubFixtures::PRODUCTION, GithubFixtures::HEAD)
      assert_empty pipeline.held(pipeline.staging)
      assert_empty Delivery::HeldMigrations.between(GithubFixtures::HEAD, GithubFixtures::HEAD)
      assert_empty Delivery::HeldMigrations.between(nil, GithubFixtures::HEAD)
    end
  end

  test "the last rehearsal of a version says how it went" do
    canned do
      pipeline = Delivery::Pipeline.new
      rehearsal = pipeline.staging.rehearsal(GithubFixtures::HEAD)
      assert_predicate rehearsal, :succeeded?
      assert_equal [ 12, 77 ], [ rehearsal.migration_seconds, rehearsal.downtime_seconds ]
      assert_nil pipeline.production.rehearsal(GithubFixtures::HEAD)
      assert_nil pipeline.staging.rehearsal(nil)
    end
  end

  test "the runs: one live, and the freeze off" do
    canned do
      pipeline = Delivery::Pipeline.new
      assert_predicate pipeline, :live?
      assert_equal [ 58 ], pipeline.live_runs.map(&:number)
      assert_equal 4, pipeline.deploy_runs.size
      assert_not pipeline.frozen?
      assert_nil pipeline.freeze_note
    end
  end

  test "the freeze, when the pipeline is frozen" do
    canned(frozen: true) do
      pipeline = Delivery::Pipeline.new
      assert_predicate pipeline, :frozen?
      assert_equal "alex · 2026-10-13 · guests this weekend", pipeline.freeze_note
    end
  end

  test "a rolled-back destination is told apart from one main left behind, and one ahead of main" do
    rollback = Delivery::Github::Record.new(id: 1, sha: GithubFixtures::OLDER, ref: GithubFixtures::OLDER, task: "rollback", environment: "production", payload: {},
                                            created_at: Time.current, state: "success", description: "rolled back", log_url: nil, finished_at: Time.current, inactive: false)
    swapping(Delivery::Github, :records, ->(**) { [ rollback ] }) do
      canned do
        pipeline = Delivery::Pipeline.new
        assert_equal :rolled_back, pipeline.sync(pipeline.production)
      end
    end

    swapping(Delivery::Github, :records, ->(**) { [] }) do
      canned { assert_equal :unknown, Delivery::Pipeline.new.sync(Delivery::Environment.new("production")) }
    end

    ahead = rollback.with(task: "deploy")
    swapping(Delivery::Github, :records, ->(**) { [ ahead ] }) do
      swapping(Delivery::Github, :compare, ->(_base, _head) { Delivery::Github::Comparison.new(status: "diverged", ahead_by: 1, behind_by: 2, commits: [], added_files: []) }) do
        canned { assert_equal :ahead, Delivery::Pipeline.new.sync(Delivery::Environment.new("production")) }
      end
    end
  end

  test "dev runs a branch: which, from a fresh preview, and where the branch stands since" do
    canned do
      pipeline = Delivery::Pipeline.new
      dev = pipeline.dev

      assert_equal GithubFixtures::DEV, dev.version
      assert_equal "fix-the-bell", dev.branch
      assert_predicate dev, :fresh?
      assert_equal "alex from the app #8: the bell rings twice", dev.deployed_by
      assert_equal :behind, pipeline.sync(dev)
      assert_equal [ "Debounce the bell" ], pipeline.pending(dev).map(&:title)
      assert_equal 1, pipeline.behind_by(dev)
      assert_not pipeline.on_main?(GithubFixtures::DEV)
      assert pipeline.on_main?(GithubFixtures::PRODUCTION)
      assert pipeline.on_main?(GithubFixtures::HEAD)
      assert_equal %w[fix-the-bell main upcoming-pagination], pipeline.branches
    end
  end

  test "a branch at its head, merged into main, gone, or not recorded" do
    preview = ->(sha, branch, task: "preview") do
      Delivery::Github::Record.new(id: 1, sha: sha, ref: sha, task: task, environment: "dev", payload: { "branch" => branch, "fresh" => "false" },
                                   created_at: Time.current, state: "success", description: "previewed", log_url: nil, finished_at: Time.current, inactive: false)
    end
    sync = ->(records) { swapping(Delivery::Github, :records, ->(**) { records }) { canned { Delivery::Pipeline.new.then { [ _1.sync(_1.dev), _1.pending(_1.dev) ] } } } }

    assert_equal [ :head, [] ], sync.call([ preview.call(GithubFixtures::BRANCH_HEAD, "fix-the-bell") ])
    assert_equal [ :merged, [] ], sync.call([ preview.call(GithubFixtures::PRODUCTION, "old-branch") ])
    assert_equal [ :gone, [] ], sync.call([ preview.call(GithubFixtures::DEV, "no-such-branch") ])
    assert_equal [ :unknown, [] ], sync.call([ preview.call(GithubFixtures::DEV, nil, task: "restart") ])
    assert_equal [ :unknown, [] ], sync.call([])

    # The branch a restart kept: the preview before it still says which.
    restarted = [ preview.call(GithubFixtures::DEV, nil, task: "restart"), preview.call(GithubFixtures::DEV, "fix-the-bell") ]
    swapping(Delivery::Github, :records, ->(**) { restarted }) { canned { assert_equal "fix-the-bell", Delivery::Pipeline.new.dev.branch } }

    # A stop keeps what ran until then, and runs nothing.
    stopped = [ preview.call(GithubFixtures::DEV, nil, task: "stop"), preview.call(GithubFixtures::DEV, "fix-the-bell") ]
    swapping(Delivery::Github, :records, ->(**) { stopped }) do
      canned do
        dev = Delivery::Pipeline.new.dev
        assert_predicate dev, :stopped?
        assert_not dev.running?
        assert_equal [ GithubFixtures::DEV, "fix-the-bell" ], [ dev.version, dev.branch ]
      end
    end
    canned { assert_predicate Delivery::Pipeline.new.dev, :running? }
  end

  test "a destination nothing was recorded for runs nothing, by nobody, from no branch" do
    swapping(Delivery::Github, :records, ->(**) { [] }) do
      canned do
        dev = Delivery::Pipeline.new.dev
        assert_equal [ nil, nil, nil, nil, nil ], [ dev.record, dev.version, dev.short_version, dev.deployed_at, dev.deployed_by ]
        assert_equal [ false, false, false, false ], [ dev.stopped?, dev.running?, dev.rolled_back?, dev.fresh? ]
        assert_nil dev.branch
      end
    end
  end

  test "the branch dev runs has a pull request whose head passed CI: ready to merge, with what main gains" do
    canned do
      pipeline = Delivery::Pipeline.new
      pull = pipeline.pull_request(pipeline.dev)
      assert_equal [ 46, "Ring the bell once per message", GithubFixtures::BRANCH_HEAD, "fix-the-bell" ], [ pull.number, pull.title, pull.head_sha, pull.head_branch ]
      assert_predicate pull, :open?
      assert_not pull.draft?
      assert_equal :ready, pipeline.merge_state(pipeline.dev)
      assert_equal [ "Debounce the bell" ], pipeline.merge_pending(pipeline.dev).map(&:title)
      assert pipeline.untested_on_dev?(pipeline.dev)
      assert_nil pipeline.pull_request(pipeline.staging)
    end
  end

  test "merge states: merged, no pull request, a draft, CI not run, running or failed on the head" do
    canned do
      state = -> { Delivery::Pipeline.new.then { _1.merge_state(_1.dev) } }
      pull = Delivery::Github.pull_request("fix-the-bell")
      run = Delivery::Github.workflow_runs(workflow: "ci.yml", branch: "fix-the-bell").first

      swapping(Delivery::Github, :pull_request, ->(_branch) { nil }) { assert_equal :none, state.call }
      swapping(Delivery::Github, :pull_request, ->(_branch) { pull.with(draft: true) }) { assert_equal :draft, state.call }
      runs = Delivery::Github.method(:workflow_runs)
      with_runs = ->(found, &block) { swapping(Delivery::Github, :workflow_runs, ->(**options) { options[:branch] == "fix-the-bell" ? found : runs.call(**options) }, &block) }
      with_runs.call([]) { assert_equal :ci_none, state.call }
      with_runs.call([ run.with(status: "in_progress", conclusion: nil) ]) { assert_equal :ci_running, state.call }
      with_runs.call([ run.with(conclusion: "failure") ]) { assert_equal :ci_failed, state.call }
      with_runs.call([ run.with(head_sha: GithubFixtures::DEV) ]) { assert_equal :ci_none, state.call }

      merged = Delivery::Github::Record.new(id: 1, sha: GithubFixtures::PRODUCTION, ref: GithubFixtures::PRODUCTION, task: "preview", environment: "dev", payload: { "branch" => "old" },
                                            created_at: Time.current, state: "success", description: "previewed", log_url: nil, finished_at: Time.current, inactive: false)
      swapping(Delivery::Github, :records, ->(**) { [ merged ] }) { assert_equal :merged, state.call }
      swapping(Delivery::Github, :records, ->(**) { [] }) { assert_equal :none, state.call }
    end
  end
end
