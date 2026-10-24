# frozen_string_literal: true

# Checks a change set without writing anything. What models file in the
# wrong place is moved first (a lab result's reference ranges become
# set_range operations, analyte-keyed fields its values), then each
# operation is checked and the set gets its status:
#   :ready        everything checked and safe, applied now
#   :confirm      complete but risky (a deletion, a possible duplicate), waits for the user's button
#   :incomplete   something missing, unclear or wrong
module Assistant
  module ChangeSets
    class Compiler
      Result = Data.define(:operations, :status, :context) do
        def ready? = status == :ready
      end

      RANGE_KEYS = /\A(?:reference_ranges?|references?|normal_ranges?|ranges?)\z/
      UNIT_IN_TEXT = %r{(?:\A|\s|\()([a-zµμ]+/[a-z0-9]+|%)(?=\s|\)|,|;|\z)}i
      BOUND_KEYS = ReferenceRangeWriter::BOUNDS + %w[range_text range]
      # The operations that carry a lab result's fields, and so its values.
      WRITES = %w[create update].freeze

      def self.call(set) = new(set).call

      def initialize(set)
        @set = set
      end

      def call
        context = Context.for(@set)
        specs = expand(@set.operations.map { |spec| Operations.normalize(spec) })
        operations = specs.each_with_index.map { |spec, i| Operations.build(spec, index: i, context: context) }
        context.supplies_bought = supplies_bought(specs)
        # Creates are checked first: a range in the same set takes its unit
        # from the values a new lab result gives (lab_units).
        operations.grep(Operations::Create).each { |op| op.compile }
        operations.grep(Operations::Create).each { |op| context.lab_units.merge!(op.lab_units) }
        operations.reject { |op| op.is_a?(Operations::Create) }.each(&:compile)
        check_handles(operations)

        status =
          if operations.empty? || operations.any? { |op| !op.ready? } then :incomplete
          elsif operations.any?(&:needs_confirmation?) then :confirm
          else :ready
          end
        Result.new(operations: operations, status: status, context: context)
      end

      private

      # The supplies this set buys, by name, with the unit each is counted
      # in: a dose in the same set may use them before they are saved.
      def supplies_bought(specs)
        creates = specs.select { |spec| spec["op"] == "create" }
        creates.filter_map { |spec| Draft.shape(spec["type"].to_s).bought_supply(spec["fields"]) }.to_h
      end

      # A lab result's ranges and analyte-keyed values become their own
      # operations and values instead of being rejected.
      def expand(specs)
        specs.flat_map { |spec| split_items(spec) }.flat_map do |spec|
          next [ spec ] unless Resources.lookup(spec["type"])&.lab_values? && WRITES.include?(spec["op"])

          fields = spec["fields"].dup
          extra = fields.keys.grep(RANGE_KEYS).flat_map { |key| range_specs(spec, fields.delete(key)) }
          known = known_lab_fields(spec["op"])
          fields.keys.each do |key|
            next if known.include?(key)

            value = fields[key]
            if value.is_a?(Hash) && (value.keys.map(&:to_s) & BOUND_KEYS).any?
              extra << range_spec(spec, value.merge("analyte" => key))
              fields.delete(key)
            elsif value.is_a?(Numeric) || value.to_s.match?(/\A\s*[<>]?\s*-?\d/)
              (fields["values"] = values_hash(fields["values"]))[key] = fields.delete(key)
            end
          end
          [ spec.merge("fields" => fields), *extra ]
        end
      end

      # One create listing several things bought ("items": ["needles", …] or
      # "needles, syringes") is one purchase per item; the item's own details
      # (a hash) win over the shared ones.
      def split_items(spec)
        items = spec["fields"]["items"]
        named = Draft.shape(spec["type"]).listed_as if spec["op"] == "create"
        return [ spec ] unless named && items.present?

        list = items.is_a?(String) ? items.split(/\s*(?:,|\band\b|\be\b)\s*/i).reject(&:blank?) : Array(items)
        shared = spec["fields"].except("items")
        list.map do |item|
          own = item.is_a?(Hash) ? item.stringify_keys : { named => item.to_s }
          spec.merge("fields" => shared.merge(own))
        end
      end

      def known_lab_fields(op)
        writable = Resources.fetch("lab_test_result").writable
        base = writable + Draft::LAB_VALUE_KEYS + %w[status recurrence remove_values date therapy collection_id medical_therapy_id occurrence_date]
        op == "create" ? base + Draft::SHARED_SECTIONS + %w[lab_test_result] : base
      end

      def values_hash(existing)
        return existing.dup if existing.is_a?(Hash)

        Draft.lab_entries(existing).to_h { |e| [ e["analyte_name"], [ e["value"], e["unit_name"] ].compact.join(" ") ] }
      end

      def range_specs(spec, given)
        items =
          case given
          when Hash then given.map { |name, s| s.is_a?(Hash) ? s.merge("analyte" => name) : { "analyte" => name, "range_text" => s } }
          when String then split_by_analyte(spec, given)
          else Array(given).flat_map { |item| item.is_a?(String) ? split_by_analyte(spec, item) : [ item ] }
          end
        items.map { |item| range_spec(spec, item) }
      end

      # "Cobalamin in pg/mL: 150 low 250 high. Vitamin D between 20 and 50"
      # is one item per analyte named in this lab result's values.
      def split_by_analyte(spec, text)
        names = Draft.lab_entries(spec["fields"].values_at(*Draft::LAB_VALUE_KEYS).compact.first).map { |e| e["analyte_name"] }
        found = names.filter_map { |name| (at = text.downcase.index(name.downcase)) && [ at, name ] }.sort
        return [ { "analyte" => nil, "range_text" => text } ] if found.empty?

        found.each_with_index.map do |(at, name), i|
          { "analyte" => name, "range_text" => text[(at + name.size)...(found[i + 1]&.first || text.size)] }
        end
      end

      def range_spec(spec, item)
        item = item.is_a?(Hash) ? item.stringify_keys : { "range_text" => item.to_s }
        text = item["range_text"] || item["range"] || item["reference"]
        item["unit"] ||= text.to_s[UNIT_IN_TEXT, 1] if text
        { "intent" => spec["intent"], "op" => "set_range", "type" => "reference_range", "fields" => item }.compact
      end

      def check_handles(operations)
        known = operations.filter_map { |op| op.spec["as"] }
        operations.each do |op|
          next unless op.ref.to_s.start_with?("$") && !known.include?(op.ref.to_s)

          op.problems << "#{op.ref} is not the \"as\" of any create in this change"
        end
      end
    end
  end
end
