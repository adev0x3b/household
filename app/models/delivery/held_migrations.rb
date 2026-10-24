# frozen_string_literal: true

module Delivery
  # The held-migration rule applied through GitHub's API, since a running copy
  # has no checkout to read.
  module HeldMigrations
    module_function

    def between(from, to)
      return [] if from.blank? || to.blank? || from == to

      ::HeldMigrations.among(Github.compare(from, to).added_files) { |path| Github.file(path, to) }
    end
  end
end
