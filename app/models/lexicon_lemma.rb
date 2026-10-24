# frozen_string_literal: true

# A noun in one language (its dictionary form) from one import.
class LexiconLemma < ApplicationRecord
  belongs_to :lexicon_import
  has_many :lexicon_forms, dependent: :delete_all
  has_many :lexicon_meanings, dependent: :delete_all
end
