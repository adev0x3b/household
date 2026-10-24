# frozen_string_literal: true

require "test_helper"

# A kaikki line reduced to forms and English meanings (or, for the pivot, synonyms).
class Lexicon::EntryTest < ActiveSupport::TestCase
  def italian(word) = sample_lines("it").map { JSON.parse(_1) }.find { _1["word"] == word && _1["pos"] == "noun" && _1["senses"]&.any? }

  test "an Italian noun: its plural, and its first meaning ranked first" do
    entry = Lexicon::Entry.from_kaikki(italian("ago"), pivot: false)

    assert_equal %w[ago aghi], entry.forms.first(2)
    assert_includes entry.meanings, [ "needle", 0, false ]
  end

  test "a narrowed meaning is qualified, after the plain ones" do
    meanings = Lexicon::Entry.from_kaikki(italian("lancetta"), pivot: false).meanings

    assert_includes meanings, [ "needle", 1, true ], "needle (of a barometer…)"
    assert_includes meanings, [ "lancet", 2, false ]
  end

  test "glosses that point at another word aren't meanings, two-word openings included" do
    glosses = [ "alternative form of ago", "synonym of ago", "name of several species of heron", "plural of ago", "short for agopuntura" ]
    data = { "pos" => "noun", "word" => "agho", "senses" => glosses.map { { "glosses" => [ _1 ] } } }

    assert_empty Lexicon::Entry.from_kaikki(data, pivot: false).meanings
  end

  test "a gloss with several meanings gives each, in every singular spelling" do
    data = { "pos" => "noun", "word" => "cerotto", "senses" => [ { "glosses" => [ "sticking plaster, plaster, band-aids" ] } ] }
    keys = Lexicon::Entry.from_kaikki(data, pivot: false).meanings.map(&:first)

    assert_equal [ "sticking plaster", "plaster", "band-aids", "band-aid" ], keys
  end

  test "a comma or semicolon inside a parenthetical or a quote doesn't cut the meaning" do
    glosses = [ "gauze (very thin fabric, generally used for medical purposes)", "tie, “band; ribbon”, bow" ]
    data = { "pos" => "noun", "word" => "Mull", "senses" => glosses.map { { "glosses" => [ _1 ] } } }
    meanings = Lexicon::Entry.from_kaikki(data, pivot: false).meanings

    assert_includes meanings, [ "gauze", 0, true ]
    assert_equal [ "tie", "bow" ], meanings.select { _2 == 1 }.map(&:first)
  end

  test "the pivot keeps synonyms, not glosses; other parts of speech are skipped" do
    vial = sample_lines("en").map { JSON.parse(_1) }.find { _1["word"] == "vial" && _1["pos"] == "noun" }
    entry = Lexicon::Entry.from_kaikki(vial, pivot: true)

    assert_includes entry.synonyms, "phial"
    assert_empty entry.meanings
    assert_nil Lexicon::Entry.from_kaikki({ "pos" => "verb", "word" => "inject" }, pivot: false)
  end
end
