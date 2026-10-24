# frozen_string_literal: true

# Starting states with parameters, written as a hash in a scenario's seed:
#
#   seed:
#     - { supplies: { Aghi: 200, Siringhe: 100 } }      # bought a week ago, for the B12 therapy
#     - { dose_series: { name: Cobalamin, day: monday } }  # a weekly injection from the next such day
#
# Kept apart from Seeds so the eval dashboard's seed list stays the named ones.
module AssistantEval
  module SeedSpecs
    module_function

    def apply(spec, profile)
      spec.to_h.each do |kind, value|
        case kind.to_s
        when "supplies" then supplies(profile, value)
        when "dose_series" then dose_series(profile, value)
        else raise ArgumentError, "unknown seed #{kind.inspect} (supplies, dose_series)"
        end
      end
    end

    def supplies(profile, quantities)
      therapy = Collection.find_by(profile: profile, name: "B12")
      quantities.to_h.each do |name, quantity|
        supply = profile.supplies.create!(name: name.to_s, category: :consumable, unit_label: "pieces")
        SupplyPurchase.create!(supply: supply, profile: profile, collection: therapy, quantity_purchased: quantity,
                               quantity_remaining: quantity, purchased_on: Date.current - 7)
      end
    end

    def dose_series(profile, options)
      options = options.to_h.stringify_keys
      day = options.fetch("day", "monday").to_s
      start = ((Date.current + 1)..(Date.current + 7)).find { _1.strftime("%A").casecmp?(day) }
      dose = Medication.new(title: options.fetch("name").to_s, starts_on: start,
                            details_attributes: { kind: :injection, quantity: 0.12, unit: "ml", area: :thigh, side: :left })
      Seeds.series!(profile, dose, recurrence: { frequency: "weekly", interval: 1, week_days: [ day ] },
                                   collection_id: Collection.find_by(profile: profile, name: "B12")&.id)
    end
  end
end
