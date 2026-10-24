# frozen_string_literal: true

require "test_helper"

# Lexicon::EvalCases: the model's answer becomes one case per concept;
# cases edited on the page survive a regeneration; a bad answer is an error
# that says what's wrong. The model is a stand-in here.
class Lexicon::EvalCasesTest < ActiveSupport::TestCase
  Answer = Data.define(:content)

  setup { @italian = lexicon_languages(:it) }

  def chat_answering(items)
    Object.new.tap { |chat| chat.define_singleton_method(:ask) { |_prompt| Answer.new(content: { "items" => items }) } }
  end

  def item(concept, plural)
    { "concept" => "#{concept} (plural: x)", "singular" => plural, "plural" => plural,
      "dose_sentence" => "Materiali: #{plural}, 1 ciascuno.", "purchase_sentence" => "Ho comprato #{plural}: 50 pezzi." }
  end

  def every_concept = Lexicon::EvalCases.concepts.map { item(_1.concept, "#{_1.concept.tr(" ", "_")}_it") }

  test "one case per concept, even when the model echoes the concept with its plural" do
    cases = Lexicon::EvalCases.generate!(@italian, chat: chat_answering(every_concept))

    assert_equal Lexicon::EvalCases.concepts.size, @italian.lexicon_eval_cases.count
    assert_equal "needle_it", cases.first.native_plural
  end

  test "a case confirmed on the page is kept when the cases are written again" do
    Lexicon::EvalCases.generate!(@italian, chat: chat_answering(every_concept))
    @italian.lexicon_eval_cases.find_by!(concept: "gauze").update!(native_plural: "garze", confirmed: true)
    Lexicon::EvalCases.generate!(@italian, chat: chat_answering(every_concept))

    assert_equal "garze", @italian.lexicon_eval_cases.find_by!(concept: "gauze").native_plural
  end

  test "the concepts a language has no case for yet are the ones to suggest" do
    assert_equal Lexicon::EvalCases.concepts.map(&:concept), Lexicon::EvalCases.missing_concepts(@italian).map(&:concept)

    Lexicon::EvalCases.generate!(@italian, chat: chat_answering(every_concept))

    assert_empty Lexicon::EvalCases.missing_concepts(@italian)
  end

  test "an answer missing concepts names them" do
    error = assert_raises(Lexicon::EvalCases::Error) { Lexicon::EvalCases.generate!(@italian, chat: chat_answering(every_concept.first(3))) }

    assert_match "the model left out", error.message
    assert_match "vial", error.message
  end

  test "a thinking model's answer is read after its thoughts, and concepts it renamed are taken in order" do
    renamed = every_concept.map { _1.merge("concept" => "something else") }
    thinking = Object.new.tap do |chat|
      chat.define_singleton_method(:ask) { |_prompt| Answer.new(content: "<think>Needles first.</think>\n#{JSON.generate(items: renamed)}") }
    end
    cases = Lexicon::EvalCases.generate!(@italian, chat: thinking)

    assert_equal Lexicon::EvalCases.concepts.map(&:concept), cases.map(&:concept)
    assert_equal "needle_it", cases.first.native_plural
  end

  test "an answer that isn't JSON says so" do
    rambling = Object.new.tap { |chat| chat.define_singleton_method(:ask) { |_prompt| Answer.new(content: "Sure! Here are the words: aghi, siringhe") } }

    error = assert_raises(Lexicon::EvalCases::Error) { Lexicon::EvalCases.generate!(@italian, chat: rambling) }
    assert_match "the model's answer isn't JSON", error.message
  end

  test "the pivot needs no cases: the templates are English already" do
    assert_empty Lexicon::EvalCases.generate!(LexiconLanguage.find_by!(code: "en"), chat: chat_answering([]))
  end
end
