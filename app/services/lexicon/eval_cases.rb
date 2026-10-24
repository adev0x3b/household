# frozen_string_literal: true

# Writes a language's eval cases (LexiconEvalCase): for every concept in
# config/lexicon_eval_concepts.yml, the noun a speaker of that language
# would label the supply with and the two things a user says with it,
# translated from English templates — by the assistant's own model, once,
# in one structured call: a draft. A case counts only once a person has
# confirmed it on the admin page (fixed or as written), because the model's
# words are often wrong ("agli" — garlic — for needle, "gause", "strips");
# a confirmed case is the truth the dictionary is then held to. Confirmed
# cases are kept when the cases are written again.
#
#   Lexicon::EvalCases.generate!(language_record)  # => [LexiconEvalCase, …]
module Lexicon
  module EvalCases
    class Error < StandardError; end

    CONCEPTS_PATH = Rails.root.join("config/lexicon_eval_concepts.yml")
    # No articles: they'd need the noun's gender in the other language. The
    # dose one says "use … per dose" plainly, since "Supplies for each
    # injection: needles, 1 each" reads as a shopping list and the assistant
    # recorded a purchase every time. A test of the dictionary mustn't hinge
    # on an ambiguous sentence.
    DOSE_TEMPLATE = "For my cobalamin injections I use %<item>s: 1 per dose, from now on."
    PURCHASE_TEMPLATE = "I bought %<item>s: 50 pieces, 10 euros, paid by card."

    Concept = Data.define(:concept, :plural, :means)

    SCHEMA = {
      type: "object",
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              concept: { type: "string" }, singular: { type: "string" }, plural: { type: "string" },
              dose_sentence: { type: "string" }, purchase_sentence: { type: "string" }
            },
            required: %w[concept singular plural dose_sentence purchase_sentence]
          }
        }
      },
      required: %w[items]
    }.freeze

    module_function

    def concepts
      YAML.load_file(CONCEPTS_PATH).map { |entry| Concept.new(concept: entry["concept"].to_s, plural: entry["plural"].to_s, means: entry["means"].to_s) }
    end

    # The shared concepts a language has no case for yet.
    def missing_concepts(language)
      taken = language.lexicon_eval_cases.pluck(:concept)
      concepts.reject { taken.include?(_1.concept) }
    end

    def dose_message(item) = format(DOSE_TEMPLATE, item: item)
    def purchase_message(item) = format(PURCHASE_TEMPLATE, item: item)

    # The pivot has none: the templates already are English.
    # chat: anything answering ask(prompt) with a #content (tests).
    def generate!(language, chat: nil)
      return [] if language.pivot?

      wanted = concepts
      answer = ask(chat || new_chat, prompt(language, wanted))
      # Models echo the concept with its "(plural: …)" — or rename it; then the answer's order decides.
      listed = Array(answer["items"])
      items = listed.index_by { |item| item["concept"].to_s.sub(/\(.*\z/, "").downcase.squish }
      items = wanted.map(&:concept).zip(listed).to_h if items.keys.intersection(wanted.map(&:concept)).empty? && listed.size == wanted.size
      missing = wanted.map(&:concept).reject { items.key?(_1) }
      raise Error, "the model left out #{missing.join(", ")}" if missing.any?

      model = "#{Assistant.provider}/#{Assistant.model}"
      wanted.map do |concept|
        item = items.fetch(concept.concept)
        record = language.lexicon_eval_cases.find_or_initialize_by(concept: concept.concept)
        next record if record.confirmed?

        record.update!(native_singular: item["singular"].to_s.squish, native_plural: item["plural"].to_s.squish,
                       dose_sentence: item["dose_sentence"].to_s.squish, purchase_sentence: item["purchase_sentence"].to_s.squish,
                       model: model)
        record
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Error, "the model's answer is incomplete: #{e.record.errors.full_messages.to_sentence}"
    end

    def prompt(language, wanted)
      name = language.wiktionary
      <<~PROMPT
        You are helping test a household app in #{name}. Translate each English item into #{name}.
        For each item write:
        - singular and plural: the everyday #{name} noun for it, as a #{name} speaker would write it on a box of these supplies —
          translated into #{name}, never the English word (unless #{name} speakers really use the English word), no article, no brand, lower case;
        - dose_sentence: "#{dose_message("{item}")}" translated into #{name}, with that plural noun where {item} is;
        - purchase_sentence: "#{purchase_message("{item}")}" translated into #{name}, with that plural noun where {item} is.
        Keep every number as it is. One entry per item, in the same order, with its concept exactly as given (just the English noun).
        For example, in German the item "spoon (plural: spoons)" would be: singular "löffel", plural "löffel",
        dose_sentence "Material für jede Cobalamin-Injektion: löffel, je 1.", purchase_sentence "Ich habe löffel gekauft: 50 Stück, 10 Euro, mit Karte bezahlt."
        Items, each with what it is (all medical supplies for injections, blood tests and small wounds):
        #{wanted.map { "- #{_1.concept} (plural: #{_1.plural}): #{_1.means}" }.join("\n")}
      PROMPT
    end

    # The English name of a case's supply: its own (a case an admin created),
    # else the shared concept's, else the English rule.
    def english_plural(kase)
      kase.english_plural.presence || concepts.find { _1.concept == kase.concept }&.plural || kase.concept.pluralize
    end

    def new_chat
      Assistant.llm_context.chat(model: Assistant.model, provider: Assistant.provider, assume_model_exists: true).with_temperature(0).with_schema(SCHEMA)
    end

    def ask(chat, prompt)
      content = chat.ask(prompt).content
      content.is_a?(Hash) ? content.stringify_keys : JSON.parse(Assistant::ModelReply.new(content).answer)
    rescue JSON::ParserError => e
      raise Error, "the model's answer isn't JSON: #{e.message.truncate(120)}"
    rescue RubyLLM::Error, Faraday::Error, SystemCallError, Timeout::Error => e
      raise Error, "the model couldn't be asked (#{Assistant.provider}/#{Assistant.model}): #{e.message.truncate(160)}"
    end
  end
end
