# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # One step of a job.
    Step = Data.define(:name, :status, :conclusion) do
      def self.from(step) = new(name: step["name"].to_s, status: step["status"].to_s, conclusion: step["conclusion"])

      def state = conclusion.presence || status.to_s
    end
  end
end
