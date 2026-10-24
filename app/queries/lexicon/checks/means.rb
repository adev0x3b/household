# frozen_string_literal: true

module Lexicon
  module Checks
    # { word: ago, means: needle, first: true } — one of its meanings.
    class Means < Meaning
      def self.kind = "means"
      def self.keys = %w[word means]

      private

      def meaning_kind = "gloss"
    end
  end
end
