# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # The code, in its own repository (Deployment.source_repository):
    # commits, comparisons, branches, a file's source, and the pull requests
    # the console merges.
    module Repository
      # A branch's head, or one commit. A sha never changes; a branch moves.
      def commit(ref)
        cached("commit/#{ref}", ref.to_s.match?(SHA) ? STILL_TTL : LIVE_TTL) { Commit.from(call(get("/commits/#{ref}", repository: source))) }
      end

      def compare(base, head)
        ttl = [ base, head ].all? { _1.to_s.match?(SHA) } ? STILL_TTL : LIVE_TTL
        cached("compare/#{base}/#{head}", ttl) { Comparison.from(call(get("/compare/#{base}...#{head}", per_page: 250, repository: source))) }
      end

      # A branch's head commit, or nil when there is no such branch (any more).
      def branch(name)
        cached("branch/#{name}", LIVE_TTL) do
          response = perform(get("/branches/#{name}", repository: source))
          response.code.to_s == "404" ? nil : Commit.from(json(response).fetch("commit"))
        end
      end

      # The branches' names, as GitHub lists them (alphabetical, the first LIMIT).
      def branches(limit: 100)
        cached("branches/#{limit.to_i}", LIVE_TTL) { call(get("/branches", per_page: limit.to_i, repository: source)).map { _1["name"].to_s } }
      end

      # A file's source at a commit.
      def file(path, ref)
        cached("file/#{ref}/#{path}", ref.to_s.match?(SHA) ? STILL_TTL : LIVE_TTL) do
          request = get("/contents/#{path}", ref: ref, repository: source)
          request["Accept"] = "application/vnd.github.raw+json"
          text(perform(request))
        end
      end

      # A branch's open pull request into main, or nil (not kept: `cached`
      # never stores nil, so a reader memoizes it for the request).
      def pull_request(branch)
        cached("pull/#{branch}", LIVE_TTL) do
          call(get("/pulls", head: "#{source.split("/").first}:#{branch}", state: "open", per_page: 1, repository: source)).first&.then { PullRequest.from(_1) }
        end
      end

      # Merges a pull request into main with a merge commit, as GitHub's button
      # does, only if its head is still `head_sha` (else GitHub answers 409:
      # the branch moved since the console showed it). Returns the merge
      # commit's sha. What the merge made stale is forgotten: main's head, the
      # branch, CI's runs on main, the pull request.
      def merge_pull_request(number, head_sha:, branch:)
        answer = call(put("/pulls/#{number.to_i}/merge", merge_method: "merge", sha: head_sha, repository: source))
        [ "commit/main", "branch/#{branch}", "pull/#{branch}", "runs/#{CI_WORKFLOW}/main/#{Pipeline::CI_LOOKBACK}" ].each { forget(_1) }
        answer["sha"].presence
      end
    end
  end
end
