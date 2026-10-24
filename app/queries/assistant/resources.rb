# frozen_string_literal: true

module Assistant
  # What the assistant can work with: one Resource per kind of record,
  # found by the type the model names or a word it uses for it. The tools
  # that read and change any record stay generic over them, so a new kind
  # of record is a new class in resources/ and a line in REGISTRY (see
  # "Record types" in docs/architecture/assistant.md).
  #
  # Summaries are short and fixed, so a small local model gets the facts it
  # needs and nothing else; the words they are made of are Words.
  module Resources
    MAX_RESULTS = 25

    extend Words

    REGISTRY = [
      Tasks, Appointments, Medications, Meals, LabTestResults, Transactions,
      Collections, Supplies, SupplyPurchases, Analytes, ReferenceRanges,
      Ingredients, IngredientPurchases, Recipes, Books, GroceryLists
    ].map(&:new).index_by(&:key).freeze

    # Words a model is likely to use for a type instead of its key.
    ALIASES = {
      "reference" => "reference_range", "range" => "reference_range", "normal_range" => "reference_range",
      "therapy" => "collection", "medical_therapy" => "collection", "group" => "collection",
      "purchase" => "supply_purchase", "groceries" => "ingredient_purchase", "grocery_purchase" => "ingredient_purchase",
      "food_purchase" => "ingredient_purchase", "expense" => "transaction",
      "payment" => "transaction", "income" => "transaction", "lab_result" => "lab_test_result",
      "lab" => "lab_test_result", "medicine" => "medication", "visit" => "appointment", "doctor" => "appointment", "todo" => "task",
      "shopping_list" => "grocery_list", "shopping" => "grocery_list",
      "novel" => "book", "libro" => "book", "bookshelf" => "book", "library" => "book",
      "dinner" => "meal", "lunch" => "meal", "breakfast" => "meal", "snack" => "meal", "meal_plan" => "meal", "restaurant" => "meal"
    }.freeze

    def self.keys = REGISTRY.keys

    def self.fetch(key)
      lookup(key) || raise(ArgumentError, "unknown type #{key.inspect}. Known: #{keys.join(", ")}")
    end

    # The resource a key or one of its aliases names, nil when none.
    def self.lookup(key)
      normalized = key.to_s.strip.underscore.tr(" -", "__").singularize
      REGISTRY[ALIASES.fetch(normalized, normalized)]
    end

    # The resource a record belongs to: a day by its series' kind.
    def self.for_record(record)
      return fetch(record.event.type.underscore) if record.is_a?(Occurrence)

      fetch(record.class.name.underscore)
    end
  end
end
