# frozen_string_literal: true

require "test_helper"

# kaikki.org's list of languages (a small page written in the shape of its
# index), and reading a language's code from the start of its extract.
class Lexicon::CatalogTest < ActiveSupport::TestCase
  test "every language kaikki.org has, biggest first, without the combined file" do
    languages = Lexicon::Catalog.parse(file_fixture("lexicon/kaikki_index.html").read)

    assert_equal [ "English", "Latin", "Spanish", "Italian", "Ye'kwana" ], languages.map(&:name), "biggest first, entities decoded, repeats and the combined file left out"
    assert_equal 1_008_871, languages.second.senses, "thousands separators read"
  end

  test "an extract's language code comes from its first entries" do
    assert_equal({ code: "it", language: "Italian" }, Lexicon::Source.new(path: file_fixture("lexicon/italian_sample.jsonl.gz")).peek)
  end

  test "a file that isn't an extract says so" do
    plain = Tempfile.new([ "plain", ".jsonl.gz" ]).tap { _1.write("not gzip") && _1.flush }

    assert_raises(Lexicon::Source::Error) { Lexicon::Source.new(path: plain.path).peek }
  end
end
