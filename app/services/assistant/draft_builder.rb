# frozen_string_literal: true

module Assistant
  # The unsaved records a Draft describes, as one kind of record has them.
  # DraftEvaluator checks the very records DraftCommitter then saves, so
  # what is missing and what gets saved can never disagree.
  class DraftBuilder
    COST_FIELDS = %w[amount payment_method counterparty currency].freeze
    # slots: the times of a day ("08:00", "CV": Events::TimesOfDay);
    # times_of_day is the older name for them.
    RECURRENCE_FIELDS = %w[frequency interval week_days ends slots times_of_day].freeze
    SHARED_FIELDS = %w[status collection_id therapy].freeze

    # What a kind's own checks make of the warnings found so far: the
    # warnings to show, and the words that refuse the call, if any.
    Screening = Data.define(:warnings, :refusal)

    # The builder for the draft's kind. The catalogs are shared across a
    # change set, so a new analyte or ingredient named twice is created
    # once; supplies_bought lets a medication's uses name a supply the same
    # set buys before it exists.
    def self.for(draft, **options) = KINDS.fetch(draft.kind).new(draft, **options)

    KINDS = {
      "appointment" => Appointments, "task" => Tasks, "medication" => Medications, "lab_test_result" => LabTestResults,
      "transaction" => Transactions, "meal" => Meals, "supply_purchase" => SupplyPurchases,
      "ingredient_purchase" => IngredientPurchases, "collection" => Collections, "ingredient" => Ingredients,
      "recipe" => Recipes, "grocery_list" => GroceryLists
    }.freeze

    attr_reader :draft, :profile

    def initialize(draft, profile:, catalog: nil, pantry_catalog: nil, supplies_bought: {})
      @draft = draft
      @profile = profile
      @lab_catalog = catalog
      @pantry_catalog = pantry_catalog
      @supplies_bought = supplies_bought
    end

    def kind = draft.kind
    def section = draft.section(kind)
    def resource = Resources.fetch(kind)
    def cost = draft.section("transaction")

    # The primary record, unsaved.
    def record = @record ||= build

    # The new series a calendar kind's draft builds; nil for the others.
    def series = nil

    # By id, or by name ("therapy": "B12", typos included) among the
    # profile's collections, a healthcare one first (Resources.collection_named).
    def collection_id
      id = (draft.payload["collection_id"] || section["collection_id"]).presence
      return id if id

      Resources.collection_named(profile, (draft.payload["therapy"] || section["therapy"]).presence)&.id
    end

    # Anything in the payload this kind would not use. Removed from the
    # draft and reported back, so nothing the model sends vanishes silently.
    # Returns paths like ["lab_test_result.test_results"].
    def prune_unknown!
      allowed_by_section.flat_map do |name, allowed|
        section = draft.payload[name]
        next [] unless section.is_a?(Hash)

        (section.keys - allowed).map do |key|
          section.delete(key)
          "#{name}.#{key}"
        end
      end
    end

    # "completed" / "pending" if the model said so, else nil.
    def requested_status = Normalize.enum(section["status"]).presence_in(%w[completed pending])

    # Whether the draft carries a price to save with it: always for a
    # purchase, when one was said for the kinds that may have one.
    def cost_requested? = cost_section == :required || (cost_section == :optional && cost_given?)

    def cost_attributes
      attrs = cost.slice(*COST_FIELDS).merge("amount" => Normalize.amount(cost["amount"]))
      attrs["payment_method"] = Normalize.payment(attrs["payment_method"])
      attrs.compact_blank
    end

    def new_ingredient_names = pantry_catalog.new_ingredient_names

    # What the kind can't find among the user's things, before its records
    # are validated: [{ "field" => …, "problem" => … }].
    def unresolved = []

    # What the kind needs that its records' validations allow blank (a
    # booked visit needs its time).
    def missing_parts = required_fields.filter_map { |field| { "field" => "#{kind}.#{field}" } if section[field].blank? }

    # Saved records the draft may repeat, as summaries.
    def duplicates = []

    # What the model should do instead when the draft looks like `existing`.
    def duplicate_hint(_existing) = nil

    # Warnings of the kind's own, beyond a possible duplicate.
    def warnings(_acknowledged) = []

    # The kind's last word on the warnings: calls a model makes again by
    # mistake are refused with what to call instead.
    def screen(warnings, _acknowledged) = Screening.new(warnings: warnings, refusal: nil)

    # What the model may want to tell the user about the draft.
    def notes = []

    # Whether the kind's create form can show the draft from the card. A
    # form is made under what the record belongs to, so a purchase whose
    # supply or ingredient is still to be created has no form yet.
    def form_opens? = true

    # The units given for a lab result's analytes, by analyte name.
    def lab_units = {}

    # Whether something it uses is still being bought in the same set.
    def waits_for_purchase? = false

    # Picks up, once they are saved, what the set's purchases bought for it.
    def use_purchases! = nil

    # Saves the records through the committer, which keeps what was saved.
    def save!(_committer) = raise(NotImplementedError, "#{self.class} must say how it is saved")

    # The card's line for it.
    def label = type_label

    private

    def build = raise(NotImplementedError, "#{self.class} must say what it builds")

    # Whether a price comes with it: nil for none, :optional, :required.
    def cost_section = nil

    def required_fields = []

    # The fields of its own section the kind reads.
    def own_fields = resource.writable + SHARED_FIELDS

    def cost_given? = cost.any? { |_, value| value.present? }

    def lab_catalog = @lab_catalog ||= LabCatalog.new(profile)
    def pantry_catalog = @pantry_catalog ||= PantryCatalog.new(profile)

    # A price said for a kind that takes none is reported as not
    # understood rather than asked about; a payment's own section is its
    # kind's.
    def allowed_by_section
      sections = { "transaction" => cost_section ? COST_FIELDS : [], "recurrence" => RECURRENCE_FIELDS }
      sections[kind] = own_fields
      sections
    end

    # The section's writable fields, enums read the way people write them.
    def writable_attributes
      section.slice(*resource.writable).to_h do |field, value|
        [ field, resource.enums.key?(field) || field == "status" ? Normalize.enum(normalize(field, value)) : normalize(field, value) ]
      end
    end

    # A field's value said another way ("bonifico"), as the kind keeps it.
    def normalize(field, value) = field == "payment_method" ? Normalize.payment(value) : value

    # A recipe's or grocery list's ingredient lines: each ingredient and
    # unit the matching catalog row (Assistant::NameMatch) or a new unsaved
    # one, created only when the draft is saved.
    def pantry_lines(key, line_class)
      Array(draft.payload[key]).filter_map do |item|
        item = item.is_a?(Hash) ? item.to_h : { "ingredient" => item.to_s }
        name = item["ingredient"].to_s.squish
        next if name.empty?

        line_class.new(ingredient: pantry_catalog.ingredient(name), quantity: item["quantity"], unit: pantry_catalog.unit(item["unit"]))
      end
    end

    def summarize(found) = resource.summarize(found, profile: profile)

    def type_label = I18n.t("assistant.types.#{kind}", default: kind.humanize)

    def with_date(text, date) = date ? I18n.t("assistant.operations.on_date", thing: text, date: I18n.l(date, format: :long)) : text

    # "Needles × 100 · €20.00": the price the purchase's payment will post.
    def with_price(text)
      cost = cost_attributes
      cents = Transaction.amount_to_cents(cost["amount"]).to_i
      return text if cents.zero?

      "#{text} · #{Reports::Money.new(cents: cents, currency: cost["currency"] || profile.household.currency)}"
    end
  end
end
