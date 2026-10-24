# frozen_string_literal: true

# The user-facing line on a deletion confirmation card, in the user's
# language: "Appointment with Moretti on 25 September 2026".
module Assistant
  module ProposalSummary
    LISTED = 10

    # One line for several records: "these 2: B12 Blood Panel on 16 September
    # 2026, Lab results on 23 September 2026".
    def self.for_many(records, scope:)
      return self.for(records.first, scope:) if records.one?

      listed = records.first(LISTED).map { |record| self.for(record, scope:) }
      listed << I18n.t("assistant.proposals.summary.more", count: records.size - LISTED) if records.size > LISTED
      I18n.t("assistant.proposals.summary.many", count: records.size, list: listed.join(", "))
    end

    def self.for(record, scope:)
      label =
        case record
        when SupplyPurchase then record.supply.name
        when IngredientPurchase then record.ingredient.name
        when Supply, Collection, Analyte, Ingredient, Recipe, GroceryList then record.name
        when ReferenceRange then I18n.t("assistant.proposals.reference_range", analyte: record.analyte.name, unit: record.unit.name)
        else record.try(:event_label) || record.try(:title).to_s
        end
      date = (record.date if record.is_a?(Occurrence)) || record.try(:purchased_on)

      if scope.to_s == "series"
        I18n.t("assistant.proposals.summary.series", label: label)
      elsif date
        I18n.t("assistant.proposals.summary.one", label: label, date: I18n.l(date, format: :long))
      else
        I18n.t("assistant.proposals.summary.undated", label: label)
      end
    end
  end
end
