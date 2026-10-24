# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # One run of a workflow (CI or Deploy).
    Run = Data.define(:id, :number, :title, :event, :status, :conclusion, :actor, :created_at, :updated_at, :html_url, :head_sha, :head_branch, :workflow) do
      # A run as GitHub's API words it. `workflow` names its workflow when the
      # list was asked for by one; a run fetched alone says it in its path.
      def self.from(run, workflow = nil)
        new(id: run["id"], number: run["run_number"], title: run["display_title"].to_s, event: run["event"], status: run["status"].to_s,
            conclusion: run["conclusion"], actor: run.dig("actor", "login"), html_url: run["html_url"],
            created_at: Time.zone.parse(run["created_at"].to_s), updated_at: Time.zone.parse(run["updated_at"].to_s),
            head_sha: run["head_sha"], head_branch: run["head_branch"], workflow: workflow || run["path"].to_s.split("/").last)
      end

      def live? = LIVE.include?(status)
      # What a badge says: how it ended, else where it is.
      def state = conclusion.presence || status.to_s
      def succeeded? = conclusion == "success"
    end
  end
end
