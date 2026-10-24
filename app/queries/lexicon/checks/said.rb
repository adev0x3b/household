# frozen_string_literal: true

module Lexicon
  module Checks
    # { said: needle, supplies: [Aghi, Siringhe], expect: Aghi } — what the
    # matcher picks among those names (expect: none — that it picks nothing).
    # It runs the real matcher with this import in place of the language's
    # active one, alongside the other languages' active imports.
    class Said < Base
      def self.kind = "said"
      def self.keys = %w[said supplies expect]

      def call
        imports = LexiconImport.active_ids.merge(@language.code => @import.id)
        matcher = Matcher.new(imports: imports, languages: Config.languages.merge(@language.code => @language))
        pick = matcher.pick(Array(@spec["supplies"]).map(&:to_s), @spec["said"].to_s)
        expected = @spec["expect"].to_s
        got = pick.name || (pick.candidates.any? ? "a tie: #{pick.candidates.join(", ")}" : "none")
        [ expected.casecmp?("none") ? pick.name.nil? : pick.name == expected, got ]
      end
    end
  end
end
