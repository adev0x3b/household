# frozen_string_literal: true

# Rebuilds test/fixtures/files/lexicon/{italian,english}_sample.jsonl.gz:
# the real kaikki.org lines of every noun the matcher benchmark and the
# config/lexicons.yml checks use (English also with the entries its
# synonyms point at, so two-way synonyms behave as on the full data), plus a
# few lines of other parts of speech the importer must skip.
#
#   bin/rails runner script/lexicon_fixture.rb /path/italian.jsonl.gz /path/english.jsonl.gz
require Rails.root.join("test/support/supply_names_benchmark")

italian_path, english_path = ARGV
abort "usage: bin/rails runner script/lexicon_fixture.rb italian.jsonl.gz english.jsonl.gz" unless italian_path && english_path

words = SupplyNamesBenchmark.words
dir = Rails.root.join("test/fixtures/files/lexicon")

def keys_of(data)
  ([ data["word"] ] + Array(data["forms"]).filter_map { _1["form"] if Array(_1["tags"]).include?("plural") }).map { Lexicon::Text.fold(_1) }
end

def pick(path, wanted)
  kept = []
  others = 0
  Zlib::GzipReader.open(path) do |gz|
    gz.each_line do |line|
      unless line.include?(Lexicon::Import::NOUN_MARK)
        kept << line if others < 3 && (others += 1)
        next
      end
      data = JSON.parse(line)
      kept << line if data["pos"] == "noun" && wanted.intersect?(keys_of(data).to_set)
    end
  end
  kept
end

# Only the fields the importer reads: an English line also carries its
# translations into every language, which would make the fixture megabytes.
KEPT = %w[pos word lang lang_code forms synonyms senses].freeze

def trim(line)
  data = JSON.parse(line).slice(*KEPT)
  data["senses"] = Array(data["senses"]).map { _1.slice("glosses", "synonyms", "tags") } if data.key?("senses")
  "#{JSON.generate(data, space: " ")}\n"
end

def write(path, lines)
  Zlib::GzipWriter.open(path) { |gz| lines.each { gz.write(trim(_1)) } }
  puts "#{path}: #{lines.size} lines"
end

write(dir.join("italian_sample.jsonl.gz"), pick(italian_path, words))

english = pick(english_path, words)
synonyms = english.flat_map do |line|
  data = JSON.parse(line)
  (Array(data["synonyms"]) + Array(data["senses"]).flat_map { Array(_1["synonyms"]) }).map { Lexicon::Text.fold(_1["word"]) }
end
write(dir.join("english_sample.jsonl.gz"), pick(english_path, words | synonyms.to_set))
