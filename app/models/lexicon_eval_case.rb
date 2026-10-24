# frozen_string_literal: true

# One supply concept (config/lexicon_eval_concepts.yml) in a language, as a
# fluent speaker would put it — written by the model (Lexicon::EvalCases) and
# editable on the admin page: the noun a household would label the supply
# with, and two things a user would say with it. Lexicon::AgentEval turns
# each into the scenarios an import is tested against the agent with.
# An admin can also create one for a supply of their own (not shared: this
# language only, with its English plural), and delete it again.
class LexiconEvalCase < ApplicationRecord
  belongs_to :lexicon_language

  normalizes :concept, with: -> { _1.to_s.squish.downcase }
  normalizes :english_plural, with: -> { _1.to_s.squish.presence }

  validates :concept, :native_singular, :native_plural, :dose_sentence, :purchase_sentence, presence: true
  validates :concept, uniqueness: { scope: :lexicon_language_id }

  # One of the supplies every language is tested with (written by the model
  # again on request), as opposed to one an admin created here.
  def shared? = Lexicon::EvalCases.concepts.any? { _1.concept == concept }
end
