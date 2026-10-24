# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # Food bought: it adds to the ingredient's stock, after creating the
    # ingredient when it is new. A price is optional, and posts as
    # groceries.
    class IngredientPurchases < DraftBuilder
      # The Ingredient it is for: the one the name clearly means (exact or
      # a typo only, never "milk" for "Oat milk"), or a new unsaved one,
      # kept in the unit the user bought it in.
      def ingredient
        @ingredient ||= begin
          name = section["ingredient_name"].to_s.squish.presence
          found = pantry_catalog.ingredient(name, strict: true) if name
          if found&.new_record? && found.unit.nil? && (unit = pantry_catalog.unit(section["unit_name"]))
            found.unit = unit
          end
          found
        end
      end

      def unresolved = ingredient ? [] : [ { "field" => "ingredient_purchase.ingredient_name" } ]

      # The same quantity of the same ingredient already bought that day: a
      # model re-sending its own message, not a second trip to the shop.
      def duplicates
        return [] unless ingredient&.persisted?

        IngredientPurchase.accessible_by(profile).where(ingredient: ingredient, purchased_on: record.purchased_on, quantity: record.quantity)
          .map { |purchase| summarize(purchase) }
      end

      def form_opens? = ingredient.present? && ingredient.persisted?

      def notes
        return [] unless ingredient

        [ ingredient.persisted? ? "adds to the existing ingredient #{ingredient.name}" : "adds the new ingredient #{ingredient.name}" ]
      end

      def save!(committer)
        purchase = record
        if ingredient.new_record?
          Pundit.authorize(profile, ingredient, :create?)
          ingredient.save!
          committer.keep(ingredient)
        end
        purchase.ingredient = ingredient
        Pundit.authorize(profile, purchase, :create?)
        purchase.save!
        committer.keep(purchase)
        return unless cost_requested?

        committer.attach_cost(purchase, date: purchase.purchased_on, title: purchase.cost_title, counterparty: cost["counterparty"],
                                        status: :completed, category: :groceries)
      end

      # "Flour × 1 kg · €2.00".
      def label
        quantity = [ record.quantity.to_s.sub(/\.?0+\z/, ""), record.unit&.name ].compact_blank.join(" ")
        with_price("#{ingredient&.name || type_label} × #{quantity}")
      end

      private

      def cost_section = :optional

      def own_fields = %w[ingredient_name quantity unit_name purchased_on collection_id therapy]

      def build
        IngredientPurchase.new(
          section.slice("quantity", "purchased_on").merge("profile" => profile, "ingredient" => ingredient, "unit" => pantry_catalog.unit(section["unit_name"]))
        ).tap { |purchase| purchase.purchased_on ||= Date.current }
      end
    end
  end
end
