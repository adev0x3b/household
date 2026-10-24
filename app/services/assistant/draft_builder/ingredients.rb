# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # An ingredient the pantry starts tracking, with no purchase.
    class Ingredients < NamedRecords
      # Unlike a therapy or a recipe, an ingredient's name is unique per
      # profile in the database (it is a catalog, not a log): even a
      # confirmed duplicate would fail on that index. So a call naming one
      # the pantry has is refused, naming the tools that add to it.
      def screen(warnings, _acknowledged)
        twin = warnings.find { |warning| warning["code"] == "possible_duplicate" }
        return super unless twin

        id = twin.dig("existing", "id")
        Screening.new(warnings: warnings - [ twin ],
                      refusal: "an ingredient named \"#{record.name}\" already exists (id #{id}). If the user bought more, use " \
                               "record_groceries (it adds to the stock); only to correct the amount on hand or its unit use " \
                               "update_record with ref #{id} (that replaces the amount) — add_ingredient is only for a name not in the pantry yet.")
      end

      private

      # The unit goes through the pantry catalog rather than
      # Ingredient#unit_name=, which only matches a name exactly: the
      # catalog also reads a close spelling and gives the set one new unit
      # however many of its drafts name it.
      def build
        ingredient = Ingredient.new(writable_attributes.except("unit_name").merge("profile" => profile))
        unit_name = section["unit_name"].to_s.squish
        ingredient.unit = pantry_catalog.unit(unit_name) if unit_name.present?
        ingredient
      end
    end
  end
end
