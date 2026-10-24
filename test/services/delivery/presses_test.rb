# frozen_string_literal: true

require "test_helper"

# The presses' modals and controller are tested through
# Admin::DeliveryRequestsController; this is what each kind decides.
class Delivery::PressesTest < ActiveSupport::TestCase
  include CannedPipeline

  isolate_env "DEPLOY_DISPATCH_TOKEN", "KAMAL_DESTINATION"
  setup { with_deploy_token }

  # A sudo window as the press sees it: open or closed, taking one password.
  Sudo = Struct.new(:open, :password) do
    def active? = open
    def verify(given) = given == password
  end

  SHA = "0123456789abcdef0123456789abcdef01234567"

  def a_run(id:, title: "", event: "workflow_dispatch", status: "completed", conclusion: "success", branch: "main", created_at: Time.current)
    Delivery::Github::Run.new(id: id, number: id, title: title, event: event, status: status, conclusion: conclusion, actor: "a", created_at: created_at,
                              updated_at: created_at, html_url: "https://github.com/example/household/actions/runs/#{id}", head_sha: SHA, head_branch: branch, workflow: "x")
  end

  def press(kind, sudo: Sudo.new(false, "secret"), **attributes)
    Delivery::Presses.for(kind).new(pipeline: Delivery::Pipeline.new, sudo: sudo, **attributes)
  end

  test "a press is found by its kind or a request's action, and an unknown kind is none" do
    assert_equal Delivery::Presses::Rollback, Delivery::Presses.for(:rollback)
    assert_equal Delivery::Presses::Merge, Delivery::Presses.for("merge")
    assert_equal Delivery::Presses::Merge, Delivery::Presses.for_action("merge_branch")
    assert_nil Delivery::Presses.for("wipe")
    assert_equal Delivery::Request.actions.keys.sort, Delivery::Presses.all.map(&:action).sort, "every action a request records has its press"
  end

  test "a freeze is done when GitHub takes it; everything else has a run to follow" do
    assert Delivery::Presses::Freeze.instant? && Delivery::Presses::Unfreeze.instant?
    assert_not Delivery::Presses.all.without(Delivery::Presses::Freeze, Delivery::Presses::Unfreeze).any?(&:instant?)
  end

  test "a deploy's run is found by the id in its name, CI's by its branch, event and time" do
    request = Delivery::Request.create!(profile: profiles(:alice), action: :rollback, destination: "production", version: SHA)
    listed = [ a_run(id: 1, title: "rollback production at #{SHA} — alice from the app ##{request.id + 1}"), a_run(id: 2, title: "deploy staging — alice from the app ##{request.id}: now", status: "in_progress", conclusion: nil) ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { listed }) { assert_equal 2, Delivery::Presses::Rollback.find_run(request).id }

    ci = Delivery::Request.create!(profile: profiles(:alice), action: :ci, ref: "fix-bell")
    listed = [ a_run(id: 3, event: "push", branch: "fix-bell"), a_run(id: 4, branch: "main"), a_run(id: 5, branch: "fix-bell", created_at: 1.hour.ago), a_run(id: 6, branch: "fix-bell") ]
    asked = nil
    swapping(Delivery::Github, :workflow_runs, ->(**options) { asked = options; listed }) { assert_equal 6, Delivery::Presses::Ci.find_run(ci).id }
    assert_equal({ workflow: "ci.yml", branch: "fix-bell", limit: 10 }, asked)
  end

  test "a merge's run is CI's on main for its merge commit, once it has one" do
    request = Delivery::Request.create!(profile: profiles(:alice), action: :merge_branch, ref: "fix-the-bell")
    swapping(Delivery::Github, :workflow_runs, ->(**) { flunk "asked" }) { assert_nil Delivery::Presses::Merge.find_run(request) }

    request.update!(version: SHA)
    listed = [ a_run(id: 1, event: "push", branch: "main"), a_run(id: 2, event: "push", branch: "main").with(head_sha: "0" * 40) ]
    asked = nil
    swapping(Delivery::Github, :workflow_runs, ->(**options) { asked = options; listed }) { assert_equal 1, Delivery::Presses::Merge.find_run(request).id }
    assert_equal({ workflow: "ci.yml", branch: "main", limit: 10 }, asked)
  end

  test "where each kind acts: fixed by its nature, the one given, or this copy when it may" do
    canned do
      assert_equal "production", press(:rollback, destination: "staging").destination
      assert_equal "dev", press(:preview, destination: "staging").destination
      assert_nil press(:merge, destination: "staging").destination
      assert_equal "demo", press(:deploy, destination: "demo").destination
      assert_nil press(:deploy, destination: "dev").destination, "main's versions never go to dev"
      assert_equal "dev", press(:restart, destination: "dev").destination

      ENV["KAMAL_DESTINATION"] = "staging"
      assert_equal "staging", press(:deploy).destination
      ENV["KAMAL_DESTINATION"] = "dev"
      assert_nil press(:deploy).destination
      assert_equal "dev", press(:restart).destination
    end
  end

  test "which version: the one given, else main's head, else the newest earlier one for a rollback" do
    canned do
      assert_equal GithubFixtures::HEAD, press(:deploy, destination: "staging").version
      assert_equal GithubFixtures::OLDER, press(:deploy, destination: "staging", version: GithubFixtures::OLDER).version
      assert_equal GithubFixtures::HEAD, press(:release).version
      assert_equal GithubFixtures::OLDER, press(:rollback).version
      assert_equal "c3c3c3c", press(:rollback).phrase
    end
  end

  test "what each kind asks of the admin" do
    canned do
      assert press(:rollback).danger? && press(:rollback).typed? && press(:rollback).reason_required? && press(:rollback).gated?
      assert press(:release).danger? && press(:release).typed? && press(:release).reason_required? && press(:release).gated?
      assert press(:freeze).reason_required? && press(:freeze).gated?
      assert_predicate press(:unfreeze), :gated?
      assert_not press(:unfreeze).reason_required?
      assert_predicate press(:deploy, destination: "production"), :gated?
      assert_not press(:deploy, destination: "staging").gated?
      assert_predicate press(:restart, destination: "production"), :gated?
      assert_not press(:restart, destination: "demo").gated?

      assert_predicate press(:release), :password?
      assert_not press(:release, sudo: Sudo.new(true, "secret")).password?, "typed lately"
    end
  end

  test "a preview starts fresh by default when nothing runs on dev, else keeps the data, unless the admin chose" do
    canned do
      assert_not press(:preview).fresh, "dev runs a branch"
      assert press(:preview, fresh: true).fresh
      swapping(Delivery::Github, :records, ->(**) { [] }) do
        assert press(:preview).fresh
        assert_not press(:preview, fresh: false).fresh
      end
    end
  end

  test "what blocks a press before anything is typed" do
    canned do
      assert_predicate press(:deploy, destination: "production", version: GithubFixtures::HEAD), :blocked?, "a held migration: release instead"
      assert_not press(:deploy, destination: "staging").blocked?
      assert_not press(:merge).blocked?, "the pull request passed CI on its head"
      assert_not press(:stop).blocked?
      swapping(Delivery::Github, :records, ->(**) { [] }) { assert_predicate press(:stop), :blocked? }
    end
  end

  test "what refuses a press, each in its own words" do
    canned do
      refused = press(:rollback, version: GithubFixtures::OLDER, typed: "nope", password: "wrong")
      assert_not refused.save(by: profiles(:alice))
      assert_equal [ "Say why: it goes with the run.", "Type c3c3c3c, the version's first seven characters, exactly.", "That isn't your password." ],
                   refused.errors.map(&:message)

      assert_not press(:preview, ref: "  ").save(by: profiles(:alice))
      assert_equal [ "Name the branch." ], press(:preview, ref: "  ").tap { _1.save(by: profiles(:alice)) }.errors.map(&:message)
      assert_equal [ "Pick where." ], press(:restart, destination: "moon").tap { _1.save(by: profiles(:alice)) }.errors.map(&:message)
      swapping(Delivery::Github, :records, ->(**) { [] }) do
        assert_equal [ "Pick a version." ], press(:rollback, reason: "back", password: "secret").tap { _1.save(by: profiles(:alice)) }.errors.map(&:message)
      end
      assert_not Delivery::Request.exists?
    end
  end

  test "a merge that isn't ready says why" do
    canned do
      swapping(Delivery::Github, :pull_request, ->(_branch) { nil }) do
        assert_equal [ "The branch has no open pull request." ], press(:merge).tap { _1.save(by: profiles(:alice)) }.errors.map(&:message)
      end
    end
  end

  test "saving records the press, dispatches it and watches for its run; a freeze is done at once" do
    canned do
      sent = nil
      swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
        assert press(:restart, destination: "staging", reason: "slow").save(by: profiles(:alice))
      end
      request = Delivery::Request.sole
      assert_equal [ "restart", "staging", "slow", "requested" ], [ request.action, request.destination, request.reason, request.status ]
      assert_equal "staging", sent[:destination]
      assert_enqueued_with(job: Delivery::WatchJob, args: [ request.id ])

      swapping(Delivery::Github, :set_variable, ->(*) { true }) do
        assert press(:freeze, reason: "guests", password: "secret").save(by: profiles(:alice))
      end
      assert_predicate Delivery::Request.freeze.sole, :succeeded?
    end
  end

  test "each press starts the Deploy workflow with what it names, and says who asked" do
    canned do
      calls = []
      swapping(Delivery::Github, :dispatch, ->(**inputs) { calls << inputs; true }) do
        assert press(:deploy, destination: "staging", version: GithubFixtures::OLDER).save(by: profiles(:alice))
        assert press(:rollback, version: GithubFixtures::OLDER, reason: "broken sign-in", typed: "c3c3c3c", password: "secret").save(by: profiles(:alice))
        assert press(:restart, destination: "dev").save(by: profiles(:alice))
        assert press(:preview, ref: "fix-the-bell", fresh: true).save(by: profiles(:alice))
        assert press(:stop).save(by: profiles(:alice))
      end

      started = calls.map { _1.except(:reason) }
      assert_equal [
        { action: "deploy", destination: "staging", version: GithubFixtures::OLDER },
        { action: "rollback", destination: "production", version: GithubFixtures::OLDER },
        { action: "restart", destination: "dev" },
        { action: "preview", destination: "dev", branch: "fix-the-bell", fresh: true },
        { action: "stop", destination: "dev" }
      ], started
      rollback = Delivery::Request.rollback.sole
      assert_equal "alice from the app ##{rollback.id}: broken sign-in", calls.second[:reason]
    end
  end

  test "a freeze sets the variable and a note of who and why; an unfreeze deletes both" do
    canned do
      set, deleted = [], []
      swapping(Delivery::Github, :set_variable, ->(name, value) { set << [ name, value ]; true }) do
        swapping(Delivery::Github, :delete_variable, ->(name) { deleted << name; true }) do
          assert press(:freeze, reason: "holiday", password: "secret").save(by: profiles(:alice))
          assert press(:unfreeze, password: "secret").save(by: profiles(:alice))
        end
      end

      assert_equal [ Delivery::Github::FREEZE, "true" ], set.first
      assert_equal Delivery::Github::FREEZE_NOTE, set.second.first
      assert_match(/\Aalice · .+ · holiday\z/, set.second.last)
      assert_equal [ Delivery::Github::FREEZE, Delivery::Github::FREEZE_NOTE ], deleted
      assert Delivery::Request.freeze.sole.succeeded? && Delivery::Request.unfreeze.sole.succeeded?
      assert_no_enqueued_jobs(only: Delivery::WatchJob)
    end
  end

  test "GitHub's refusal marks the request failed and is raised for the caller to tell" do
    canned do
      refused = ->(**) { raise Delivery::Github::Error, "GitHub answered 422: no such ref" }
      swapping(Delivery::Github, :dispatch_ci, refused) do
        assert_raises(Delivery::Github::Error) { press(:ci, ref: "gone").save(by: profiles(:alice)) }
      end
      request = Delivery::Request.sole
      assert_equal [ "failed", "GitHub answered 422: no such ref" ], [ request.status, request.summary ]

      unreachable = ->(*) { raise Delivery::Github::Error, "GitHub answered 502" }
      swapping(Delivery::HeldMigrations, :between, unreachable) do
        assert_raises(Delivery::Github::Error) { press(:deploy, destination: "production", password: "secret").save(by: profiles(:alice)) }
      end
      assert_equal 1, Delivery::Request.count, "refused while checking: nothing was recorded"
    end
  end
end
