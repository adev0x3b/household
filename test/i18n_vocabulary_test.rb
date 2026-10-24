# frozen_string_literal: true

require "test_helper"

# Every concept has one word on screen, in each language (the table is
# docs/architecture/glossary.md). This reads the values of the locale files
# and fails on the synonyms a concept used to have, so a string written from
# habit or copied from an old screen is caught before it ships.
#
# Only a word that means something else nowhere in the app can be refused
# here: "conversation" stays allowed because housemates have conversations,
# and "spesa" because it is also the groceries. A rule that has to allow one
# place names it in `except`.
class I18nVocabularyTest < ActiveSupport::TestCase
  Rule = Data.define(:pattern, :say, :example, :except) do
    def initialize(pattern:, say:, example:, except: nil) = super

    def exempt?(key) = except&.match?(key)
  end

  RULES = {
    en: [
      Rule.new(pattern: /\blab (tests?|reports?|values?)\b/i, say: "lab result, and its values", example: "Merge the lab tests"),
      Rule.new(pattern: /\bnormal range\b/i, say: "reference range", example: "The normal range"),
      Rule.new(pattern: /\breadings\b/i, say: "values", example: "Latest readings"),
      Rule.new(pattern: /\bspend(ing)?\b/i, say: "expenses", example: "Healthcare spending"),
      Rule.new(pattern: /\bhousehold members?\b/i, say: "housemate", example: "Share with a household member"),
      Rule.new(pattern: /\boperators?\b/i, say: "admin", example: "Ask the operator"),
      Rule.new(pattern: /\bpictures?\b/i, say: "photo", example: "Send a picture"),
      Rule.new(pattern: /pantry (&|and) meals/i, say: "Pantry", example: "Pantry & meals"),
      Rule.new(pattern: /\btake (it|them) back\b|\btaken back\b/i, say: "withdraw the request", example: "Take it back"),
      Rule.new(pattern: /\A(?!%\{\w+\} — ).*? — /m, say: "a colon or two sentences, not a dash between clauses", example: "Saved — all done",
               except: /\Ahome\.finance\.kpis\.hints\.savings_rate\z/)
    ],
    it: [
      Rule.new(pattern: /famigli/i, say: "casa", example: "La tua famiglia"),
      Rule.new(pattern: /coinquilin/i, say: "membro della casa", example: "Un coinquilino"),
      Rule.new(pattern: /operator/i, say: "amministratore", example: "L'operatore"),
      Rule.new(pattern: /\bcancellat/i, say: "annullato", example: "Cancellato"),
      Rule.new(pattern: /fornitor/i, say: "Provider (Fornitura is the supply)", example: "Fornitore"),
      Rule.new(pattern: /esame di laboratorio/i, say: "esame", example: "Nuovo esame di laboratorio"),
      Rule.new(pattern: /risultat\w* di laboratorio|valori di laboratorio|misurazion/i, say: "valori", example: "Valori di laboratorio"),
      Rule.new(pattern: /intervallo normale/i, say: "intervallo di riferimento", example: "Intervallo normale"),
      Rule.new(pattern: /\bpillol/i, say: "compressa", example: "Una pillola"),
      Rule.new(pattern: /storico acquisti/i, say: "cronologia acquisti", example: "Storico acquisti"),
      Rule.new(pattern: /opzional/i, say: "(facoltativo)", example: "Nota (opzionale)"),
      Rule.new(pattern: /casi di test|percentuale di successo|non conteggiat/i, say: "casi di prova, tasso di successo, non valutato", example: "Casi di test"),
      Rule.new(pattern: /distribui/i, say: "deploy", example: "Distribuire la versione"),
      Rule.new(pattern: /processo dei job/i, say: "worker dei job", example: "Il processo dei job"),
      Rule.new(pattern: /dispensa e pasti/i, say: "Dispensa", example: "Dispensa e pasti"),
      Rule.new(pattern: /annulla modifiche/i, say: "Ripristina", example: "Annulla modifiche"),
      Rule.new(pattern: /\bspese\b(?! sanitarie)/i, say: "uscite", example: "Le spese del mese", except: /\Ahome\.healthcare\./),
      Rule.new(pattern: /\A(?!%\{\w+\} — ).*? — /m, say: "i due punti o due frasi, non un trattino tra due frasi", example: "Fatto — tutto",
               except: /\Ahome\.finance\.kpis\.hints\.savings_rate\z/)
    ]
  }.freeze

  test "each rule matches the words it was written to refuse" do
    RULES.each_value do |rules|
      rules.each { |rule| assert_match rule.pattern, rule.example, "the rule saying #{rule.say.inspect} no longer matches its example" }
    end
  end

  test "a language says one word per concept, never an old synonym" do
    RULES.each do |locale, rules|
      found = values_of(locale).flat_map do |key, value|
        rules.filter_map do |rule|
          "#{locale}.#{key}: #{value.inspect} (say #{rule.say})" if rule.pattern.match?(value) && !rule.exempt?(key)
        end
      end

      assert_empty found, "Words the glossary retired (docs/architecture/glossary.md):"
    end
  end

  private

  def values_of(locale)
    flatten(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).fetch(locale.to_s)).select { |_key, value| value.is_a?(String) }
  end

  def flatten(tree, path = [])
    tree.flat_map do |key, value|
      value.is_a?(Hash) ? flatten(value, path + [ key ]) : [ [ (path + [ key ]).join("."), value ] ]
    end
  end
end
