# frozen_string_literal: true

# The lexicon's languages as the importer and the matcher read them: the
# lexicon_languages table, whose starting set is config/lexicons.yml
# (`defaults`). Reading them never writes.
module Lexicon
  module Config
    PATH = Rails.root.join("config/lexicons.yml")
    SOURCE = "https://kaikki.org/dictionary/%<name>s/kaikki.org-dictionary-%<file>s.jsonl.gz"
    HEADS = %w[first last].freeze

    class Unknown < StandardError; end

    # One hand-written check, as the YAML spells it; its kind and the keys it
    # needs are one of Lexicon::Checks.
    Check = Data.define(:spec) do
      def kind = Lexicon::Checks.of(spec)&.kind

      # What's wrong with it, or nil.
      def problem
        return "#{spec.to_json}: not a check (use #{Lexicon::Checks.all.map { _1.keys.join("/") }.to_sentence(last_word_connector: " or ")})" unless kind
        return "#{spec.to_json}: still TODO" if spec.values.flatten.any? { |value| value.to_s.include?("TODO") }

        missing = Lexicon::Checks.of(spec).keys - spec.keys
        "#{spec.to_json}: missing #{missing.join(", ")}" if missing.any?
      end

      def to_s = spec.map { |key, value| "#{key}: #{Array(value).join(", ")}" }.join(" · ")
    end

    Language = Data.define(:code, :wiktionary, :role, :head, :min_lemmas, :checks) do
      def pivot? = role == "pivot"
      def head_first? = head == "first"

      def url
        name = ERB::Util.url_encode(wiktionary)
        format(SOURCE, name: name, file: name)
      end

      def problems
        problems = []
        problems << "wiktionary: kaikki.org's name of the language is missing" if wiktionary.blank?
        problems << "head: must be one of #{HEADS.join(", ")}" unless HEADS.include?(head)
        problems << "min_lemmas: must be a positive number" unless min_lemmas.to_i.positive?
        problems << "role: only \"pivot\" is known" if role.present? && !pivot?
        problems + checks.filter_map(&:problem)
      end
    end

    module_function

    # Every language, by code (the pivot first).
    def languages
      LexiconLanguage.by_code.to_h { |record| [ record.code, record.to_config ] }
    end

    # config/lexicons.yml: the starting set.
    def defaults = (YAML.load_file(PATH) || {}).to_h { |code, entry| [ code.to_s, parse(code, entry) ] }

    def parse(code, entry)
      entry = entry.to_h.stringify_keys
      Language.new(code: code.to_s, wiktionary: entry["wiktionary"].to_s, role: entry["role"].to_s, head: entry["head"].to_s,
                   min_lemmas: entry["min_lemmas"].to_i, checks: Array(entry["checks"]).map { |spec| Check.new(spec: spec.to_h.stringify_keys) })
    end

    def codes = languages.keys

    def fetch(code)
      languages.fetch(code.to_s) do
        raise Unknown, "no language \"#{code}\" — add it on /admin/lexicons, or with bin/rails \"lexicon:add[<Name>]\""
      end
    end

    def pivot = languages.values.find(&:pivot?)

    # Everything wrong with the languages, each prefixed by its code.
    def problems
      pivots = languages.values.count(&:pivot?)
      list = languages.values.flat_map { |language| language.problems.map { "#{language.code}: #{_1}" } }
      list << "exactly one language must have role: pivot (found #{pivots})" unless pivots == 1
      list
    end
  end
end
