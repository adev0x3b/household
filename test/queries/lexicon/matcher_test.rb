# frozen_string_literal: true

require "test_helper"

# The supply-name benchmark (SupplyNamesBenchmark) on real Wiktionary lines:
# a wrong match draws stock from the wrong supply, so the bar is zero wrong
# and every unrelated word left unmatched; the correct count only goes up.
class Lexicon::MatcherTest < ActiveSupport::TestCase
  CORRECT_AT_LEAST = 42

  setup { import_lexicons }

  test "the benchmark: never a wrong supply, nothing for unrelated words, and at least #{CORRECT_AT_LEAST} right" do
    matcher = Lexicon::Matcher.new
    tally, rows = SupplyNamesBenchmark.run { |supplies, said| matcher.pick(supplies, said).name }
    wrong = rows.select { _1.last == :wrong }.map { |said, want, got| "#{said} → #{got} (meant #{want.inspect})" }

    assert_empty wrong
    assert_equal rows.count { _1[1].nil? }, tally[:correct_none].to_i
    assert_operator tally[:correct].to_i, :>=, CORRECT_AT_LEAST, rows.select { _1.last == :missed }.map(&:first).inspect
  end

  test "an earlier, plain meaning beats a later, narrowed one" do
    pick = Lexicon::Matcher.new.pick(%w[Aghi Lancette], "needle")

    assert_equal "Aghi", pick.name, "ago: needle (1st) — lancetta: needle (of a barometer), 2nd"
  end

  test "a tie is no match, with the tied names as candidates" do
    pick = Lexicon::Matcher.new.pick([ "Aghi", "Aghi sottili" ], "needle")

    assert_nil pick.name
    assert_equal [ "Aghi", "Aghi sottili" ], pick.candidates
  end

  test "English forms and two-way synonyms come from the English import" do
    matcher = Lexicon::Matcher.new

    assert_equal "Latex gloves", matcher.pick([ "Needles", "Latex gloves" ], "gloves").name
    assert_equal "Fiale", matcher.pick(%w[Aghi Fiale], "vial").name, "vial ↔ phial, fiala: phial"
  end

  test "without imports it knows only the same spelling" do
    matcher = Lexicon::Matcher.new(imports: {})

    assert_nil matcher.pick(%w[Aghi Siringhe], "needle").name
    assert_equal "Needles", matcher.pick(%w[Needles Syringes], "needle").name
  end

  # German, whose names end in their noun: a word the dictionary doesn't list
  # is read as a compound. The glosses are kaikki.org's.
  GERMAN = {
    "Streifen" => [ %w[stripe strip band], [] ], "Test" => [ %w[test], %w[Tests] ], "Watte" => [ [ "cotton wool" ], %w[Watten] ],
    "Bausch" => [ %w[wad pad], %w[Bäusche] ], "Handschuh" => [ [ "any handwear; glove, mitten" ], %w[Handschuhe] ],
    "Stäbchen" => [ [ "rod (in the retina)", "chopstick" ], [] ], "Spritze" => [ %w[syringe injection], %w[Spritzen] ]
  }.freeze

  def german!
    LexiconLanguage.create!(code: "de", wiktionary: "German", role: "translated", head: "last", min_lemmas: 1)
      .lexicon_eval_cases.create!(concept: "syringe", native_singular: "Spritze", native_plural: "Spritzen", confirmed: true,
                                  dose_sentence: "Spritzen, je 1.", purchase_sentence: "Ich habe Spritzen gekauft.")
    lines = GERMAN.map do |word, (glosses, plurals)|
      { pos: "noun", word: word, lang_code: "de", senses: glosses.map { { glosses: [ _1 ] } },
        forms: plurals.map { { form: _1, tags: [ "plural" ] } } }.to_json
    end
    import = Lexicon::Import.call(Lexicon::Config.fetch("de"), source: gzip_lines(lines).path, force: true, agent: :skip)
    assert_predicate import, :awaiting_review?, "too few cases: waits for review with its rows — #{import.error}"
    Lexicon::Matcher.new(imports: LexiconImport.active_ids.merge("de" => import.id))
  end

  test "German compounds the dictionary doesn't list are read from the noun they end with" do
    matcher = german!

    assert_equal "Test strips", matcher.pick([ "Test strips", "Gloves", "Syringes" ], "Teststreifen").name
    assert_equal "Teststreifen", matcher.pick(%w[Teststreifen Handschuhe Spritzen], "test strips").name
    assert_equal "Gloves", matcher.pick([ "Gloves", "Test strips" ], "Einmalhandschuhe").name, "einmal isn't a noun: the head is enough"
    assert_equal "Einmalhandschuhe", matcher.pick(%w[Einmalhandschuhe Spritzen], "Handschuhe").name
  end

  test "a compound's first noun is a weak word: it links to a meaning, never two compounds to each other" do
    matcher = german!

    assert_equal "Cotton wool", matcher.pick([ "Cotton wool", "Syringes" ], "Wattebäusche").name, "Bausch is a wad; Watte is cotton wool"
    assert_nil matcher.pick(%w[Wattestäbchen Spritzen], "Wattebäusche").name, "both have Watte, as cotton balls and swabs have cotton"
  end

  test "a language whose names start with their noun is never split" do
    assert_nil Lexicon::Matcher.new.pick(%w[Needles Syringes], "portaaghi").name
  end

  test "find returns the record of a scope" do
    profile = AssistantEval::Sandbox.profile!
    aghi = profile.supplies.create!(name: "Aghi", category: :consumable, unit_label: "pieces")
    profile.supplies.create!(name: "Siringhe", category: :consumable, unit_label: "pieces")

    assert_equal aghi, Lexicon::Matcher.find(profile.supplies, "needles")
  end

  test "LEXICON_IMPORTS puts a candidate import in place of the active one (the agent eval's process)" do
    candidate = import_lexicon("it")
    LexiconImport.where(id: candidate.id).update_all(status: LexiconImport.statuses[:running])

    with_env("LEXICON_IMPORTS" => "it=#{candidate.id}") do
      assert_equal candidate.id, Lexicon::Matcher.default_imports["it"]
    end
  end
end
