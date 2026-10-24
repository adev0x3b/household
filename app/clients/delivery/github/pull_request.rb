# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # A branch's pull request into main, as the console merges it.
    PullRequest = Data.define(:number, :title, :html_url, :state, :draft, :head_sha, :head_branch, :author, :created_at) do
      def self.from(pull)
        new(number: pull["number"], title: pull["title"].to_s, html_url: pull["html_url"], state: pull["state"].to_s, draft: pull["draft"] == true,
            head_sha: pull.dig("head", "sha"), head_branch: pull.dig("head", "ref"), author: pull.dig("user", "login"),
            created_at: Time.zone.parse(pull["created_at"].to_s))
      end

      def open? = state == "open"
      def draft? = draft == true
    end
  end
end
