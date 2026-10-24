# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # One job of a run, with its steps: what the console shows of a run in progress.
    Job = Data.define(:id, :name, :status, :conclusion, :started_at, :completed_at, :html_url, :steps) do
      def self.from(job)
        new(id: job["id"], name: job["name"].to_s, status: job["status"].to_s, conclusion: job["conclusion"], html_url: job["html_url"],
            started_at: Time.zone.parse(job["started_at"].to_s), completed_at: Time.zone.parse(job["completed_at"].to_s),
            steps: job.fetch("steps", []).map { |step| Step.from(step) })
      end

      def live? = LIVE.include?(status)
      def state = conclusion.presence || status.to_s
    end
  end
end
