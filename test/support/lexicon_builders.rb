# frozen_string_literal: true

# Imports the real-line kaikki samples (test/fixtures/files/lexicon/,
# script/lexicon_fixture.rb) the way lexicon:import would, with each
# language's real checks — only min_lemmas is lowered to fit a sample.
module LexiconBuilders
  LEXICON_FIXTURES = Rails.root.join("test/fixtures/files/lexicon")
  LEXICON_SAMPLES = { "it" => "italian_sample.jsonl.gz", "en" => "english_sample.jsonl.gz" }.freeze

  def lexicon_language(code, **changes) = Lexicon::Config.fetch(code).with(min_lemmas: 1, **changes)

  # agent: :skip by default (no model in tests); a callable stands in for Lexicon::AgentEval.
  # Italian gets confirmed test cases first (italian_cases!), so its dictionary check runs for real.
  def import_lexicon(code, source: LEXICON_FIXTURES.join(LEXICON_SAMPLES.fetch(code)), agent: :skip, cases: true, **changes)
    italian_cases! if code == "it" && cases
    Lexicon::Import.call(lexicon_language(code, **changes), source: source.to_s, force: true, agent: agent)
  end

  # Confirmed Italian test cases whose words the fixture holds: { concept => [singular, plural] }.
  ITALIAN_CASES = { "needle" => %w[ago aghi], "syringe" => %w[siringa siringhe], "plaster" => %w[cerotto cerotti],
                    "glove" => %w[guanto guanti] }.freeze

  def italian_cases!(cases = ITALIAN_CASES, confirmed: true)
    italian = LexiconLanguage.find_by!(code: "it")
    cases.each do |concept, (one, many)|
      italian.lexicon_eval_cases.find_or_create_by!(concept: concept) do |kase|
        kase.assign_attributes(native_singular: one, native_plural: many, confirmed: confirmed,
                               dose_sentence: "Per le mie iniezioni di cobalamina uso #{many}: 1 per dose, da ora in poi.",
                               purchase_sentence: "Ho comprato #{many}: 50 pezzi, 10 euro, pagati con carta.")
      end
    end
    italian
  end

  # Both samples, English (the pivot) first, as lexicon:import does.
  def import_lexicons = %w[en it].map { |code| import_lexicon(code).tap { |i| raise "#{code}: #{i.error}" unless i.active? } }

  # A .jsonl.gz of these lines, for imports that should break. The test holds
  # on to it: a Tempfile nothing refers to goes when the garbage collector
  # gets to it, which can be before the import opens it.
  def gzip_lines(lines)
    file = Tempfile.new([ "lexicon", ".jsonl.gz" ])
    Zlib::GzipWriter.open(file.path) { |gz| lines.each { gz.write("#{_1}\n") } }
    (@gzip_files ||= []) << file
    file
  end

  def sample_lines(code) = Zlib::GzipReader.open(LEXICON_FIXTURES.join(LEXICON_SAMPLES.fetch(code)), &:readlines).map(&:chomp)
end
