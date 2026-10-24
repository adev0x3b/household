# frozen_string_literal: true

# A way a lemma is written: itself and its plurals ("aghi" → ago).
class LexiconForm < ApplicationRecord
  belongs_to :lexicon_import
  belongs_to :lexicon_lemma
end
