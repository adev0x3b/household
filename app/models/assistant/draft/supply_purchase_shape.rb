# frozen_string_literal: true

class Assistant::Draft
  # A supply bought: named in a nested "supply" ({"name": …, "quantity": …})
  # or with its count in the name ("100 needles").
  class SupplyPurchaseShape < Shape
    NESTED = { "id" => "supply_id", "name" => "supply_name", "unit" => "supply_unit",
               "category" => "supply_category", "quantity" => "quantity_purchased" }.freeze
    COUNTED = /\A\s*(\d+(?:[.,]\d+)?)\s*(?:x\s+)?(.+)\z/i

    def bought_supply(fields)
      section = normalize(fields)[kind].to_h
      name = section["supply_name"].to_s.squish
      [ name, section["supply_unit"] || section["unit"] ] if name.present?
    end

    private

    def unnest(section)
      return section unless section["supply"].is_a?(Hash)

      flat = section.except("supply")
      section["supply"].each { |key, value| flat[NESTED.fetch(key, key)] ||= value }
      flat
    end

    def split_count(renamed)
      counted = renamed["supply_name"].to_s.match(COUNTED) if renamed["quantity_purchased"].blank?
      return renamed unless counted

      renamed.merge("quantity_purchased" => counted[1].tr(",", "."), "supply_name" => counted[2].strip)
    end
  end
end
