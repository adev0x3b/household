# frozen_string_literal: true

# How the lexicon compares words: folded (lower case, no accents, single
# spaces), and English read in every spelling of its singular — as written,
# Rails' singular, and without a plain trailing s (Rails makes "gloves"
# "glofe"; the English import knows better, this is the fallback).
module Lexicon
  module Text
    module_function

    def fold(text) = text.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").squish

    def words(text) = fold(text).split

    def english_keys(phrase)
      words = fold(phrase).split
      return [] if words.empty?

      [ words.join(" "), words.map(&:singularize).join(" "), words.map { _1.sub(/(?<!s)s\z/, "") }.join(" ") ].uniq
    end
  end
end
