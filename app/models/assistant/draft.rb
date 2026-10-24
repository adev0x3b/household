# frozen_string_literal: true

# One record the assistant wants to create, or a bundle such as an
# appointment and its fee, as plain data. A create operation holds it while
# it is checked and saved: Assistant::DraftBuilder turns it into unsaved
# records, Assistant::DraftEvaluator says what is missing and
# Assistant::DraftCommitter saves it.
#
# The payload holds the kind's own fields under its name, beside the shared
# sections: the cost under "transaction", the repeat under "recurrence", and
# so on. A collection is named by the user's word for it ("therapy": "B12")
# and matched to one, a healthcare one first, when the draft is built.
class Assistant::Draft
  SHARED_SECTIONS = %w[transaction recurrence collection_id therapy entries uses steps ingredients items recipes].freeze
  # Other names models give the shared sections at the top level. A Shape
  # also reads "collection" as a therapy's name, except in a collection's
  # own draft.
  SHARED_ALIASES = { "therapy_id" => "collection_id", "medical_therapy_id" => "collection_id", "therapy_name" => "therapy",
                     "medical_therapy" => "therapy", "collection_name" => "therapy" }.freeze
  COST_KEYS = { "amount" => "amount", "price" => "amount", "cost" => "amount", "payment_method" => "payment_method",
                "paid_with" => "payment_method", "counterparty" => "counterparty", "currency" => "currency" }.freeze
  DEFAULT_ALIASES = { "occurrence_date" => "date" }.freeze
  DATED_ALIASES = { "occurrence_date" => "date", "description" => "notes" }.freeze
  DATE_FIELDS = %w[date purchased_on expires_on opened_on].freeze
  # The draft's name for a field a record validates under another name, so
  # a problem is reported in the words the model used.
  FIELD_NAMES = { "starts_on" => "date", "rrule" => "recurrence" }.freeze

  # Each kind a draft can be, and how its fields are read (Draft::Shape).
  SHAPES = {
    "appointment" => Shape.new(
      "appointment",
      identity: %w[counterpart title],
      aliases: DATED_ALIASES.merge("time" => "start_time", "doctor" => "counterpart", "provider" => "counterpart",
                                   "with" => "counterpart")
    ),
    "supply_purchase" => SupplyPurchaseShape.new(
      "supply_purchase",
      identity: %w[supply_id supply_name],
      listed_as: "supply",
      aliases: { "supply" => "supply_name", "name" => "supply_name", "item" => "supply_name",
                 "quantity" => "quantity_purchased", "qty" => "quantity_purchased", "date" => "purchased_on",
                 "therapy_id" => "collection_id", "medical_therapy_id" => "collection_id" }
    ),
    "transaction" => TransactionShape.new("transaction", identity: %w[title counterparty], aliases: DATED_ALIASES),
    "task" => Shape.new("task", identity: %w[title], aliases: DATED_ALIASES),
    "medication" => Shape.new(
      "medication",
      identity: %w[title],
      aliases: DATED_ALIASES.merge("name" => "title", "scheduled_time" => "time", "timing_anchor" => "anchor",
                                   "not_taken_reason" => "skipped_reason", "reason" => "skipped_reason")
    ),
    "lab_test_result" => LabTestResultShape.new("lab_test_result", identity: %w[title], aliases: DATED_ALIASES),
    "collection" => CollectionShape.new("collection", identity: %w[name], aliases: { "description" => "notes", "title" => "name" }),
    "ingredient" => Shape.new("ingredient", identity: %w[name]),
    "ingredient_purchase" => Shape.new(
      "ingredient_purchase",
      identity: %w[ingredient_name],
      listed_as: "ingredient",
      aliases: { "ingredient" => "ingredient_name", "name" => "ingredient_name", "item" => "ingredient_name",
                 "unit" => "unit_name", "date" => "purchased_on" }
    ),
    "recipe" => Shape.new("recipe", identity: %w[name]),
    "grocery_list" => Shape.new("grocery_list", identity: %w[name]),
    "meal" => Shape.new(
      "meal",
      identity: %w[date meal_type title],
      aliases: { "occurrence_date" => "date", "type" => "meal_type", "name" => "title", "restaurant" => "title", "place" => "title" }
    )
  }.freeze
  KINDS = SHAPES.keys.freeze

  attr_accessor :kind, :payload, :missing, :warnings, :acknowledged_warnings, :profile, :chat

  def initialize(kind:, profile:, chat: nil, payload: {}, acknowledged_warnings: [])
    @kind = kind.to_s
    @profile = profile
    @chat = chat
    @payload = payload.to_h.deep_stringify_keys
    @missing = []
    @warnings = []
    @acknowledged_warnings = acknowledged_warnings
  end

  # How a kind's fields are read; a kind no draft is (an update's analyte
  # or book) only has its fields renamed.
  def self.shape(kind) = SHAPES.fetch(kind) { Shape.new(kind) }

  # The fields filed under their sections (Draft::Shape#normalize).
  def self.normalize_payload(kind, fields) = shape(kind).normalize(fields)

  # A section's fields under our names (Draft::Shape#rename).
  def self.rename_fields(kind, section) = shape(kind).rename(section)

  # Where models put a lab result's values, and the names they give an entry's parts.
  LAB_VALUE_KEYS = %w[entries values results test_results lab_values analytes].freeze
  ENTRY_NAME_KEYS = %w[analyte_name analyte name test marker].freeze
  ENTRY_VALUE_KEYS = %w[value result level].freeze
  ENTRY_UNIT_KEYS = %w[unit_name unit units].freeze
  VALUE_WITH_UNIT = /\A([<>]?\s*[-+]?\d+(?:[.,]\d+)?)\s*([^\d\s].*)?\z/

  def self.lab_entries(raw)
    items =
      case raw
      when Hash then raw.map { |name, value| value.is_a?(Hash) ? value.merge("analyte_name" => name) : { "analyte_name" => name, "value" => value } }
      when Array then raw
      when String then raw.split(/[\n;]+/)
      else []
      end

    items.filter_map do |item|
      item = parse_lab_line(item) if item.is_a?(String)
      next unless item.is_a?(Hash)

      item = item.transform_keys(&:to_s)
      name = item.values_at(*ENTRY_NAME_KEYS).find(&:present?).to_s.strip
      value = item.values_at(*ENTRY_VALUE_KEYS).find { |v| !v.nil? && v.to_s.strip != "" }.to_s.strip
      unit = item.values_at(*ENTRY_UNIT_KEYS).find(&:present?).to_s.strip
      if unit.empty? && (m = value.match(VALUE_WITH_UNIT))
        value, unit = m[1].delete(" "), m[2].to_s.strip
      end
      next if name.empty? || value.empty?

      { "analyte_name" => name, "value" => value.sub(/\A([-+]?\d+),(\d+)\z/, '\1.\2'), "unit_name" => unit.presence }.compact
    end
  end

  # "Cobalamin: 250 pg/mL" or "Cobalamin 250" as a name and a value.
  def self.parse_lab_line(line)
    m = line.strip.match(/\A(.+?)\s*[:=]\s*(.+)\z/) || line.strip.match(/\A(.*?[[:alpha:]].*?)\s+([<>]?[-+]?\d.*)\z/)
    m && { "analyte_name" => m[1], "value" => m[2] }
  end

  # Deep-merges new fields into the payload; nil values clear a field.
  def merge_payload(fields)
    merged = payload.deep_merge(self.class.normalize_payload(kind, fields))
    self.payload = merged.transform_values { |v| v.is_a?(Hash) ? v.compact : v }.compact
  end

  def section(name) = payload.fetch(name.to_s, {}).to_h

  # Same item when either side names nothing yet, or every identifying field
  # both name agrees. Naming it by different fields (a supply by id vs. by
  # name) can't be told apart, so it counts as a different item.
  def self.same_item?(wanted, have)
    return true if wanted.empty? || have.empty?

    shared = wanted.keys & have.keys
    shared.any? && shared.all? { |field| wanted[field] == have[field] }
  end

  # The identifying fields a section has, normalized for comparison.
  def self.identity(kind, section) = shape(kind).identity(section)

  def ready? = missing.empty? && warnings.empty?

  # Fields that identify this item, for merging a later mention into it.
  def identity = self.class.identity(kind, section(kind))
end
