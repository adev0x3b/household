# frozen_string_literal: true

# What a lemma means, as an English key: a gloss of a translated language's
# noun ("ago" → needle, rank 0), or a synonym of an English one ("vial" →
# phial). rank is the sense's position; qualified marks a narrowed sense
# ("needle (of a barometer)").
class LexiconMeaning < ApplicationRecord
  enum :kind, { gloss: 0, synonym: 1 }

  belongs_to :lexicon_import
  belongs_to :lexicon_lemma
end
