# frozen_string_literal: true

require "test_helper"

# The languages: config/lexicons.yml's are saved once and never
# overwritten, reading them saves nothing, every language is complete, one
# is the pivot, and every language the app speaks has a lexicon.
class Lexicon::ConfigTest < ActiveSupport::TestCase
  test "every language is complete and exactly one is the pivot" do
    assert_empty Lexicon::Config.problems
    assert_equal "en", Lexicon::Config.pivot.code
  end

  test "every language of the app has a lexicon in config/lexicons.yml" do
    missing = I18n.available_locales.map(&:to_s) - Lexicon::Config.defaults.keys
    assert_empty missing, 'add them to config/lexicons.yml (see "The lexicon" in docs/architecture/assistant.md)'
  end

  test "the starting languages are saved once; edits made since are kept" do
    lexicon_languages(:en).update!(min_lemmas: 5)
    lexicon_languages(:it).destroy!
    LexiconLanguage.ensure_defaults!

    assert_equal Lexicon::Config.defaults.keys.sort, LexiconLanguage.pluck(:code).sort
    assert_equal 5, Lexicon::Config.fetch("en").min_lemmas
  end

  test "reading the languages saves nothing, even one config/lexicons.yml has and the table doesn't" do
    lexicon_languages(:it).destroy!

    assert_no_difference -> { LexiconLanguage.count } do
      assert_equal [ "en" ], Lexicon::Config.codes
      assert_raises(Lexicon::Config::Unknown) { Lexicon::Config.fetch("it") }
    end
  end

  test "a language added outside the YAML is a language like the others" do
    LexiconLanguage.create!(code: "es", wiktionary: "Spanish", head: "first")

    assert_equal "Spanish", Lexicon::Config.fetch("es").wiktionary
    assert_empty Lexicon::Config.fetch("es").problems, "hand checks are optional"
  end

  test "an unfinished or broken entry is reported, check by check" do
    language = Lexicon::Config.parse("es", "wiktionary" => "", "head" => "middle", "min_lemmas" => 0,
                                           "checks" => [ { "form" => "TODO", "lemma" => "x" }, { "nonsense" => 1 } ])
    problems = language.problems.join("\n")

    assert_match "wiktionary", problems
    assert_match "head: must be one of first, last", problems
    assert_match "min_lemmas", problems
    assert_match "still TODO", problems
    assert_match "not a check", problems
  end

  test "a language's download address comes from its kaikki.org name" do
    language = Lexicon::Config.parse("nb", "wiktionary" => "Norwegian Bokmål", "head" => "first", "min_lemmas" => 1)

    assert_equal "https://kaikki.org/dictionary/Norwegian%20Bokm%C3%A5l/kaikki.org-dictionary-Norwegian%20Bokm%C3%A5l.jsonl.gz", language.url
  end

  test "an unknown language says how to add it" do
    error = assert_raises(Lexicon::Config::Unknown) { Lexicon::Config.fetch("xx") }
    assert_match "/admin/lexicons", error.message
  end
end
