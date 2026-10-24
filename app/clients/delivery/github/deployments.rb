# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # The Deployments API: what kamal.yml records of every action, and how
    # each went.
    module Deployments
      def deployments(environment: nil, task: nil, sha: nil, limit: 30)
        cached("deployments/#{environment}/#{task}/#{sha}/#{limit.to_i}", LIVE_TTL) do
          call(get("/deployments", environment: environment, task: task, sha: sha, per_page: limit.to_i)).map { |deployment| Record.from(deployment) }
        end
      end

      # A deployment's statuses, newest first. Once it has ended they never
      # change, so they're kept for a day.
      def deployment_statuses(id)
        cached("statuses/#{id.to_i}", ->(statuses) { statuses.any? && !LIVE_STATES.include?(statuses.first.state) ? STILL_TTL : LIVE_TTL }) do
          call(get("/deployments/#{id.to_i}/statuses", per_page: 10)).map { |status| Status.from(status) }
        end
      end

      # Deployments with their last status folded in.
      def records(environment: nil, task: nil, sha: nil, limit: 30)
        deployments(environment: environment, task: task, sha: sha, limit: limit).map { |record| record.with_statuses(deployment_statuses(record.id)) }
      end
    end
  end
end
