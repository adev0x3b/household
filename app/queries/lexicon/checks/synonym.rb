# frozen_string_literal: true

module Lexicon
  module Checks
    # { word: vial, synonym: phial } — a two-way synonym (pivot).
    class Synonym < Meaning
      def self.kind = "synonym"
      def self.keys = %w[word synonym]

      private

      def meaning_kind = "synonym"
    end
  end
end
