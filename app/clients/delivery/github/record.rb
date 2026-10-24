# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # One of kamal.yml's deployments: what it put where and who asked. How it
    # went comes from its statuses, folded in by `with_statuses`.
    Record = Data.define(:id, :sha, :ref, :task, :environment, :payload, :created_at, :state, :description, :log_url, :finished_at, :inactive) do
      # A deployment as GitHub lists it, its statuses not read yet. The
      # payload is the JSON kamal.yml wrote; {} for one that isn't.
      def self.from(deployment)
        payload = deployment["payload"]
        payload = json_object(payload) if payload.is_a?(String)
        new(id: deployment["id"], sha: deployment["sha"], ref: deployment["ref"], task: deployment["task"].to_s, environment: deployment["environment"].to_s,
            payload: payload.is_a?(Hash) ? payload : {}, created_at: Time.zone.parse(deployment["created_at"].to_s),
            state: nil, description: "", log_url: nil, finished_at: nil, inactive: false)
      end

      def self.json_object(payload)
        JSON.parse(payload)
      rescue JSON::ParserError
        {}
      end
      private_class_method :json_object

      # GitHub marks a deployment `inactive` once a newer one to the same
      # place succeeds, so the status that says how it went is the newest
      # one that isn't.
      def with_statuses(statuses)
        last = statuses.find { _1.state != "inactive" }
        with(state: last&.state, description: last&.description.to_s, log_url: last&.log_url,
             finished_at: (last.created_at if last && !LIVE_STATES.include?(last.state)), inactive: statuses.first&.state == "inactive")
      end

      def short = sha.to_s.first(7)
      def live? = state.nil? || LIVE_STATES.include?(state)
      def succeeded? = state == "success"
      def failed? = %w[failure error].include?(state)
      def requested_by = payload["requested_by"].presence
      def running_before = payload["running_before"].presence
      def run_url = payload["run_url"].presence || log_url
      # "migration 12 s · behind the page 77 s", as kamal.yml words it.
      def migration_seconds = description.to_s[/migration (\d+) s/, 1]&.to_i
      def downtime_seconds = description.to_s[/behind the page (\d+) s/, 1]&.to_i
      def held? = description.to_s.start_with?("held:")
      def undone? = description.to_s.start_with?("undone:")
      # A preview's branch, and whether it started from fresh data.
      def branch = payload["branch"].presence
      def fresh? = payload["fresh"].to_s == "true"
    end
  end
end
