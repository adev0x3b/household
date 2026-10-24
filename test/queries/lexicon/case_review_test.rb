# frozen_string_literal: true

require "test_helper"

# Lexicon::CaseReview: which of a language's eval cases count, and the hint
# each waiting one carries for whoever reviews it.
class Lexicon::CaseReviewTest < ActiveSupport::TestCase
  test "confirmed cases count once each; the others wait with what looks wrong" do
    import_lexicons
    italian = LexiconLanguage.find_by!(code: "it")
    italian.lexicon_eval_cases.create!(concept: "gauze", native_singular: "gause", native_plural: "gause", confirmed: false,
                                       dose_sentence: "uso gause", purchase_sentence: "ho comprato gause")
    italian.lexicon_eval_cases.create!(concept: "lancet", native_singular: "ago", native_plural: "aghi", confirmed: true,
                                       dose_sentence: "uso aghi", purchase_sentence: "ho comprato aghi")
    italian.lexicon_eval_cases.create!(concept: "tweezers", native_singular: "siringa", native_plural: "siringhe", confirmed: false,
                                       dose_sentence: "uso siringhe", purchase_sentence: "ho comprato siringhe")
    review = Lexicon::CaseReview.new(italian.lexicon_eval_cases.order(:id).to_a, italian, LexiconImport.active_ids)

    assert_equal %w[needle syringe plaster glove], review.counted.map(&:concept)
    assert_equal({ "gauze" => :not_in_dictionary, "lancet" => :duplicate, "tweezers" => :unlinked },
                 review.waiting.to_h { |kase, reason| [ kase.concept, reason ] })
  end
end
