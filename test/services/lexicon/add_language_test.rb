# frozen_string_literal: true

require "test_helper"

# Lexicon::AddLanguage: a language comes from its English name alone, its
# code read from kaikki.org's extract (`peek` stands in for the download).
# What it refuses comes back as an error on :wiktionary, worded for the
# admin page's form.
class Lexicon::AddLanguageTest < ActiveSupport::TestCase
  def add(name, code: "es", head: "first")
    Lexicon::AddLanguage.call(name, head: head, peek: ->(_url) { { code: code, language: name } })
  end

  test "a language kaikki.org has is saved with the code its extract carries" do
    result = add(" Spanish ")

    assert_predicate result, :success?
    assert_equal [ "Spanish", "es", "first", "translated" ], result.language.slice(:wiktionary, :code, :head, :role).values
  end

  test "a blank name, a language already here, or a code another language uses is refused, saying which" do
    assert_equal [ "can't be blank" ], add("  ").language.errors[:wiktionary]
    assert_equal [ "Italian is already here." ], add("Italian").language.errors[:wiktionary]
    assert_equal [ "kaikki.org's Italiano has the code \"it\", which Italian already uses here." ], add("Italiano", code: "it").language.errors[:wiktionary]
    assert_not LexiconLanguage.exists?(wiktionary: [ "", "Italiano" ])
  end

  test "a language kaikki.org doesn't have is refused with what it answered" do
    result = Lexicon::AddLanguage.call("Klingon", head: "", peek: ->(_url) { raise Lexicon::Source::Error, "answered 404 Not Found" })

    assert_predicate result, :failure?
    assert_equal [ "kaikki.org has no Klingon extract (answered 404 Not Found)." ], result.language.errors[:wiktionary]
  end
end
