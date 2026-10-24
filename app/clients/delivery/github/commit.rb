# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # A commit: its message's first line, who made it and when.
    Commit = Data.define(:sha, :title, :author, :committed_at, :html_url) do
      # The author is their GitHub login when GitHub knows them, else the
      # name in the commit.
      def self.from(commit)
        new(sha: commit["sha"], title: commit.dig("commit", "message").to_s.lines.first.to_s.strip,
            author: commit.dig("author", "login") || commit.dig("commit", "author", "name"),
            committed_at: Time.zone.parse((commit.dig("commit", "committer", "date") || commit.dig("commit", "author", "date")).to_s),
            html_url: commit["html_url"])
      end

      def short = sha.to_s.first(7)
    end
  end
end
