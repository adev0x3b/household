# frozen_string_literal: true

module Lexicon
  module Checks
    # A word's meanings of one kind hold the one wanted (`first: true`: in
    # its first sense, not narrowed). Means and Synonym say which kind.
    class Meaning < Base
      def call
        lemma_ids = LexiconLemma.where(lexicon_import_id: @import.id, key: Text.fold(@spec["word"])).pluck(:id)
        meanings = LexiconMeaning.where(lexicon_lemma_id: lemma_ids, kind: meaning_kind).order(:rank).pluck(:key, :rank, :qualified)
        keys = Text.english_keys(wanted.to_s)
        found = meanings.select { |key, _, _| keys.include?(key) }
        found = found.select { |_, rank, qualified| rank.zero? && !qualified } if @spec["first"]
        [ found.any?, meanings.map(&:first).uniq.first(6).join(", ") ]
      end

      private

      def wanted = @spec[self.class.kind]
      def meaning_kind = raise(NotImplementedError, "#{self.class.name} names the kind of meaning it reads")
    end
  end
end
