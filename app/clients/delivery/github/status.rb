# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # One status of a deployment: kamal.yml's word on how it went.
    Status = Data.define(:state, :description, :log_url, :created_at) do
      def self.from(status)
        new(state: status["state"].to_s, description: status["description"].to_s, log_url: status["log_url"].presence || status["target_url"].presence,
            created_at: Time.zone.parse(status["created_at"].to_s))
      end
    end
  end
end
