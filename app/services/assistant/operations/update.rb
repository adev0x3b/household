# frozen_string_literal: true

module Assistant
  module Operations
    # Changes an existing record, found by ref. Whatever the fields carry
    # beyond the record's own columns (a lab result's values, a price, a new
    # repeat) is a Part of its own, so each is checked, written and undone
    # on its own terms.
    class Update < Base
      ITEM_FIELDS = %w[items remove_items check_items uncheck_items].freeze
      RECIPE_FIELDS = %w[recipes remove_recipes].freeze
      # What a part reads, never a column of the record.
      PART_FIELDS = [ "recurrence", "remove_values", "uses", *Draft::LAB_VALUE_KEYS, *ITEM_FIELDS, *RECIPE_FIELDS ].freeze

      # A day's own columns, never the series'.
      DAY_COLUMNS = %w[date time anchor skipped_reason completed_at].freeze
      # What every series has, and a day may override.
      SERIES_COLUMNS = Occurrences::FormSave::FIELDS.map(&:to_s).freeze
      # A kind's fields that are facts about the whole series, never one day
      # (a payment between housemates is with that person every time).
      SERIES_ONLY = { "transaction" => %w[counterparty counterparty_profile_id counterparty_mode] }.freeze
      DETAILS_SKIPPED = %w[id event_id occurrence_id created_at updated_at].freeze

      # A price is set on the record's attached payment. Models call its
      # amount the cost, the price or the fee; a summary's cost_id and
      # cost_status echoed back aren't changes.
      COST_FIELDS = %w[amount payment_method].freeze
      COST_WORDS = %w[cost price fee].freeze
      COST_ECHOES = %w[cost_id cost_status].freeze

      attr_reader :record

      def phase = :changing

      def checked_records = [ record ].compact

      def check
        @record = resolve!(from_fields: false)
        return unless record

        query = record.persisted? ? :update? : :edit?
        Pundit.authorize(profile, record, query)
        ask_owner_for([ record ], query)

        @fields = build_fields
        @parts = build_parts
        fail!("nothing to change") if @fields.empty? && @parts.empty?

        [ *@parts, @fields ].each do |part|
          part.check
          @problems.concat(part.problems)
          @notes.concat(part.notes)
        end
        note_who_sees
      end

      # Who sees the record now, and whoever the change lets in: a housemate
      # the payment is now with, the people a therapy it moves into is
      # shared with.
      def seen_by
        return [] unless record

        @seen_by ||= (resource.readers(record) + let_in).excluding(profile).uniq
      end

      def preview_rows = @fields.preview_rows

      def waits_for_purchase? = @supplies.present? && @supplies.waits_for_purchase?

      def apply!(applier)
        return @parts.first.apply_alone!(applier) if series_alone?

        before = [ @fields, *@parts ].map(&:before).reduce(:merge)
        entries = [ @fields, *@parts ].flat_map { |part| part.apply!(applier) }
        GroceryLists::Broadcaster.changed(record) if record.is_a?(GroceryList)
        applier.saved([ summarize(record.reload) ])
        [ entry("updated", record, **before, **@fields.outcome), *entries ]
      end

      def label
        return super unless record

        text = label_of(record)
        date = (record.date if day?)
        return @supplies.label(text, date, only_supplies: @fields.empty? && @price.nil?) if @supplies&.checked?

        date ? I18n.t("assistant.operations.on_date", thing: text, date: I18n.l(date, format: :long)) : text
      end

      private

      def let_in
        changes = @fields&.changes.to_h
        therapy = Collection.accessible_by(profile).find_by(id: changes["collection_id"]) if changes["collection_id"].present?
        [ Profile.find_by(id: changes["counterparty_profile_id"]), *therapy&.shared_profiles ].compact
      end

      # Only the supplies change: "event_id 42" means the series from its next dose on.
      def upcoming_ref? = fields.keys == [ "uses" ]

      def day? = record.is_a?(Occurrence)

      def label_of(record) = record.try(:event_label) || record.try(:name) || record.try(:title) || I18n.t("assistant.types.#{type}", default: type.to_s.humanize)

      # A day's change that is all about its series: a new repeat, or what
      # each dose uses.
      def series_alone? = day? && @fields.empty? && @parts.all?(&:series_level?)

      # The record's own fields, renamed to its columns, with a price taken
      # out for its own part.
      def build_fields
        changes = Draft.rename_fields(resource.key, fields.except(*PART_FIELDS))
        @cost = resource.costable? ? price_changes!(changes) : {}
        unknown = changes.keys - resource.writable
        fail!("unknown fields #{unknown.join(", ")}; allowed: #{allowed_fields.join(", ")}") if unknown.any?

        fields_class = day? ? DayFields : RecordFields
        fields_class.new(record, changes, enums: resource.enums, profile: profile)
      end

      def price_changes!(changes)
        COST_WORDS.each { |word| changes["amount"] ||= changes.delete(word) if changes.key?(word) }
        changes.except!(*COST_ECHOES)
        changes.extract!(*COST_FIELDS)
      end

      def allowed_fields
        allowed = resource.writable
        allowed += [ "uses (the supplies each dose uses from now on)" ] if resource.doses?
        allowed += COST_FIELDS.map { |field| "#{field} (its fee)" } if resource.costable?
        allowed
      end

      # Each kind of change the fields carry, in the order they are written,
      # after the record's own fields. What each dose uses reads the
      # record's own changes (a new quantity), so the fields are built
      # before the parts.
      def build_parts
        @supplies = dose_supplies
        @price = (Price.new(record, @cost, profile: profile, name: label_of(record)) if @cost.any?)
        [ meal_recipes, lab_entries, recurrence, grocery_items, @price, @supplies ].compact
      end

      def meal_recipes
        part = MealRecipes.new(record, add: fields["recipes"], remove: fields["remove_recipes"], profile: profile)
        return unless part.any?

        fail!("#{RECIPE_FIELDS.join(", ")} can only be used on a meal") unless resource.recipes?
        part
      end

      def lab_entries
        entries = Draft::LAB_VALUE_KEYS.flat_map { |key| Draft.lab_entries(fields[key]) if fields.key?(key) }.compact
        part = LabEntries.new(record, entries: entries, remove: Array(fields["remove_values"]).map(&:to_s), context: context)
        return unless part.any?

        fail!("values can only be changed on a lab_test_result") unless resource.lab_values?
        part
      end

      def grocery_items
        part = GroceryItems.new(record, add: fields["items"], remove: fields["remove_items"],
                                        check: fields["check_items"], uncheck: fields["uncheck_items"], context: context)
        return unless part.any?

        fail!("#{ITEM_FIELDS.join(", ")} can only be used on a grocery_list") unless resource.list_items?
        part
      end

      def recurrence
        given = fields["recurrence"].presence
        Recurrence.new(record, given, profile: profile) if given
      end

      def dose_supplies
        raw = fields["uses"].presence
        return unless raw

        fail!("uses is only for a medication") unless resource.doses?
        fail!("change the supplies and the repeat in two separate calls") if fields["recurrence"].present?
        DoseSupplies.new(record, raw, changes: @fields.changes, context: context)
      end
    end
  end
end
