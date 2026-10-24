# frozen_string_literal: true

module Lexicon
  module Checks
    # { form: aghi, lemma: ago } — the form belongs to that lemma.
    class Form < Base
      def self.kind = "form"
      def self.keys = %w[form lemma]

      def call
        lemmas = LexiconForm.where(lexicon_import_id: @import.id, key: Text.fold(@spec["form"]))
          .joins(:lexicon_lemma).distinct.pluck("lexicon_lemmas.key")
        [ lemmas.include?(Text.fold(@spec["lemma"])), lemmas.join(", ") ]
      end
    end
  end
end
