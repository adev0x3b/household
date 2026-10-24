# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # Two commits compared: the commits head adds over base, the files it adds.
    Comparison = Data.define(:status, :ahead_by, :behind_by, :commits, :added_files) do
      def self.from(answer)
        new(status: answer["status"], ahead_by: answer["ahead_by"].to_i, behind_by: answer["behind_by"].to_i,
            commits: answer.fetch("commits", []).map { |commit| Commit.from(commit) },
            added_files: answer.fetch("files", []).select { _1["status"] == "added" }.map { _1["filename"] })
      end
    end
  end
end
