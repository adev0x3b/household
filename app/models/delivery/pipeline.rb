# frozen_string_literal: true

module Delivery
  # What GitHub says about every destination, for one request. Each answer
  # is read once and only when asked, so a frame that needs none of it asks
  # GitHub nothing.
  class Pipeline
    BRANCH = "main"
    RUNS = 8
    CI_LOOKBACK = 10

    def dev = (@dev ||= Environment.new("dev"))
    def staging = (@staging ||= Environment.new("staging"))
    def demo = (@demo ||= Environment.new("demo"))
    def production = (@production ||= Environment.new("production"))
    # In the order a change travels: a branch on dev, then main on staging and the demo, then production.
    def environments = [ dev, staging, demo, production ]
    # The ones fed from main.
    def mainline = [ staging, demo, production ]
    def environment(name) = environments.find { _1.name == name.to_s }

    def head = (@head ||= commit(BRANCH))

    # A commit by its sha or a branch's name, asked once however many cards name it.
    def commit(ref)
      @commits ||= {}
      @commits[ref] ||= Github.commit(ref)
    end

    # What a run is doing: its jobs, each with its steps.
    def jobs(run)
      @jobs ||= {}
      @jobs[run.id] ||= Github.run_jobs(run)
    end

    # CI's newest run of main's head commit, if any.
    def ci
      return @ci if defined?(@ci)

      @ci = ci_run_for(BRANCH, head.sha)
    end

    # :none (never ran), :running, :passed, :failed (or cancelled).
    def ci_state = state_of(ci)

    # CI's newest run of a commit on a branch (a pull request's head: CI runs on the pull request).
    def ci_run_for(branch, sha)
      Github.workflow_runs(workflow: Github::CI_WORKFLOW, branch: branch, limit: CI_LOOKBACK).find { _1.head_sha == sha }
    end

    def state_of(run)
      return :none unless run
      return :running if run.live?

      run.succeeded? ? :passed : :failed
    end

    # CI's image job built main's head: its tag is deployable. The job is
    # image.yml's, so GitHub names it "image / build".
    def image_built?
      return false unless ci&.succeeded?

      jobs(ci).find { _1.name == "image" || _1.name.start_with?("image / ") }&.state == "success"
    end

    # The branches a preview can pick from.
    def branches = (@branches ||= Github.branches)

    # The open pull request of the branch a destination runs (dev's), if any.
    def pull_request(environment)
      @pull_requests ||= {}
      @pull_requests.fetch(environment.name) { @pull_requests[environment.name] = environment.branch && Github.pull_request(environment.branch) }
    end

    # Can the branch dev runs be merged into main from here? :merged (it is
    # on main already), :none (no branch, or no open pull request: CI runs
    # on pull requests only), :draft, then CI on the pull request's head
    # (:ci_none, :ci_running, :ci_failed) and :ready when it passed. Main
    # has no branch protection, so this is the gate; a conflict is
    # GitHub's refusal at the merge.
    def merge_state(environment)
      return :merged if sync(environment) == :merged

      pull = pull_request(environment)
      return :none if pull.nil?
      return :draft if pull.draft?

      case state_of(ci_run_for(pull.head_branch, pull.head_sha))
      when :passed then :ready
      when :running then :ci_running
      when :failed then :ci_failed
      else :ci_none
      end
    end

    # What main gains from the pull request, oldest first.
    def merge_pending(environment)
      pull = pull_request(environment)
      return [] if pull.nil?

      commits_between(head.sha, pull.head_sha)
    end

    # Dev ran an older commit of the branch than the pull request's head.
    def untested_on_dev?(environment)
      pull = pull_request(environment)
      return false if pull.nil?

      pull.head_sha != environment.version
    end

    # How a destination stands against what feeds it. Staging, the demo and
    # production, against main: :unknown (nothing recorded), :head (runs
    # main's head), :rolled_back (an older version, on purpose), :behind
    # (main moved on), :ahead (a version main doesn't have: deployed by hand
    # from elsewhere). Dev, against its branch: :head (runs the branch's
    # head), :behind (the branch moved on), :merged (its commit is on main
    # now: the branch is done), :gone (no such branch any more), :unknown.
    def sync(environment)
      return :unknown if environment.version.blank?
      return branch_sync(environment) if environment.dev?
      return :head if environment.version == head.sha

      case comparison(environment.version, head.sha).status
      when "ahead" then environment.rolled_back? ? :rolled_back : :behind
      when "behind", "diverged" then :ahead
      else :head
      end
    end

    # The commits the destination lacks, oldest first: main's for staging,
    # the demo and production, the branch's for dev.
    def pending(environment)
      return [] if environment.version.blank?

      target = environment.dev? ? branch_head(environment)&.sha : head.sha
      return [] if target.blank? || environment.version == target

      comparison(environment.version, target).commits
    end

    def behind_by(environment) = pending(environment).size

    # Is the commit on main (merged, or main's own)?
    def on_main?(sha)
      return false if sha.blank?
      return true if sha == head.sha

      %w[ahead identical].include?(comparison(sha, head.sha).status)
    end

    # The commits `to` adds over `from` (a promotion: production's version to staging's).
    def commits_between(from, to)
      return [] if from.blank? || to.blank? || from == to

      comparison(from, to).commits
    end

    # The migrations between two versions that need the app stopped.
    def held_between(from, to)
      @held ||= {}
      @held[[ from, to ]] ||= HeldMigrations.between(from, to)
    end

    # Does moving the destination to main's head need the app stopped?
    def held(environment) = held_between(environment.version, head.sha)

    def frozen?
      return @frozen if defined?(@frozen)

      @frozen = Github.frozen?
    end

    # What the admin wrote when freezing; nil when nothing is frozen.
    def freeze_note
      return @freeze_note if defined?(@freeze_note)

      @freeze_note = Github.variable(Github::FREEZE_NOTE)
    end

    # This copy answers from canned files rather than GitHub (Github::Canned).
    def canned? = Github::Canned.on?

    def deploy_runs = (@deploy_runs ||= Github.workflow_runs(limit: RUNS))
    def live_runs = deploy_runs.select(&:live?) + [ ci ].compact.select(&:live?)
    def live? = live_runs.any? || environments.any? { _1.last&.live? }

    private

    def branch_sync(environment)
      return :merged if on_main?(environment.version)
      return :unknown if environment.branch.blank?

      head = branch_head(environment)
      return :gone if head.nil?

      head.sha == environment.version ? :head : :behind
    end

    # The head of the branch dev runs; nil when the branch is gone (or unknown).
    def branch_head(environment)
      @branch_heads ||= {}
      @branch_heads.fetch(environment.name) { @branch_heads[environment.name] = environment.branch && Github.branch(environment.branch) }
    end

    def comparison(base, head)
      @comparisons ||= {}
      @comparisons[[ base, head ]] ||= Github.compare(base, head)
    end
  end
end
