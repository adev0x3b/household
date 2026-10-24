# frozen_string_literal: true

require "test_helper"

# Lexicon::Checks: the kinds of hand-written check a language's YAML can
# hold, each a class found by the first key of its spec.
class Lexicon::ChecksTest < ActiveSupport::TestCase
  setup do
    import_lexicons
    @italian = Lexicon::Config.fetch("it")
    @english = Lexicon::Config.fetch("en")
  end

  def check(language, spec)
    import = LexiconImport.active_for(language.code)
    Lexicon::Checks.of(spec).new(import, language, spec).call
  end

  test "a spec is a check of the class whose key it carries" do
    assert_equal Lexicon::Checks::Form, Lexicon::Checks.of({ "form" => "aghi", "lemma" => "ago" })
    assert_equal Lexicon::Checks::Synonym, Lexicon::Checks.of({ "word" => "vial", "synonym" => "phial" })
    assert_equal Lexicon::Checks::Said, Lexicon::Checks.named("said")
    assert_nil Lexicon::Checks.of({ "nonsense" => 1 })
    assert_equal %w[form means synonym said], Lexicon::Checks.all.map(&:kind)
  end

  test "form: the form belongs to the lemma" do
    ok, got = check(@italian, { "form" => "aghi", "lemma" => "ago" })

    assert ok, got
    assert_includes got, "ago"
    assert_equal false, check(@italian, { "form" => "aghi", "lemma" => "siringa" }).first
  end

  test "means: the word has that meaning, in its first sense when asked" do
    ok, got = check(@italian, { "word" => "ago", "means" => "needle", "first" => true })

    assert ok, got
    assert_equal false, check(@italian, { "word" => "ago", "means" => "fork" }).first
  end

  test "synonym: the pivot's word lists it both ways" do
    assert_equal true, check(@english, { "word" => "vial", "synonym" => "phial" }).first
    assert_equal false, check(@english, { "word" => "vial", "synonym" => "jar" }).first
  end

  test "said: what the matcher picks among those names, or that it picks nothing" do
    assert_equal [ true, "Aghi" ], check(@italian, { "said" => "needle", "supplies" => %w[Aghi Siringhe], "expect" => "Aghi" })
    assert_equal [ true, "none" ], check(@italian, { "said" => "termometro", "supplies" => %w[Aghi], "expect" => "none" })
    assert_equal false, check(@italian, { "said" => "needle", "supplies" => %w[Aghi Siringhe], "expect" => "Siringhe" }).first
  end
end
