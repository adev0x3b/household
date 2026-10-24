# frozen_string_literal: true

module Assistant
  module Resources
    # The words a record's summary is made of: an amount, a day, a dose's
    # supplies, a lab value, what a payment is about. Every Resource
    # includes it for its summaries, and Resources extends it for the
    # operations' card lines: `Resources.money(cost)`.
    module Words
      # "50.0 EUR": a payment's amount (an Occurrence of a Transaction).
      def money(cost)
        return unless cost

        details = cost.details
        "#{details.amount} #{details.currency}"
      end

      # "Metformin on 9 October 2026, with dinner": a thing on its day, and
      # which dose of the day when the record has a time.
      def on_date(text, record)
        date = I18n.l(record.date, format: :long)
        if (at = record.try(:when_label))
          I18n.t("assistant.operations.on_date_at", thing: text, date: date, when: at)
        else
          I18n.t("assistant.operations.on_date", thing: text, date: date)
        end
      end

      # A supply's unit worth saying after its quantity (ml, mg, IU…); a count
      # ("pieces", "siringhe") reads better as "× 1".
      MEASURE_UNIT = /\A(?:[mµk]?[gl]|mcg|m?i?u|ui)\z/i

      # "Cobalamin 0.12 ml" or "Syringes × 1": one supply a dose uses. With
      # `locale`, the quantity is written the way that language writes it,
      # for the card.
      def supply_use(name, quantity, unit, locale: nil)
        amount = if locale
          ActiveSupport::NumberHelper.number_to_rounded(quantity, precision: 3, strip_insignificant_zeros: true, locale: locale)
        else
          quantity.to_d.to_s("F").delete_suffix(".0")
        end
        unit.to_s.match?(MEASURE_UNIT) ? "#{name} #{amount} #{unit}" : "#{name} × #{amount}"
      end

      # The supplies a dose is planned to use (its own list, else its
      # series'), saved or just built, for the model.
      def supply_uses(occurrence)
        occurrence.details.resolved_uses.map { |use| supply_use(use.supply.name, use.quantity, use.supply.unit_label) }
      end

      # "Cobalamin on 5 October 2026, using Syringes × 1, Needles × 1" for the
      # card; lines are [name, quantity, unit].
      def with_supplies(text, lines)
        return text if lines.empty?

        supplies = lines.map { |name, quantity, unit| supply_use(name, quantity, unit, locale: I18n.locale) }.join(", ")
        I18n.t("assistant.operations.with_supplies", thing: text, supplies: supplies)
      end

      # "Cobalamin: 250 pg/mL (normal)": the flag appears once a reference
      # range for that analyte and unit exists. A page of reports has its
      # entries, analytes and ranges read beforehand (Resources::LabTestResults).
      def lab_values(occurrence)
        occurrence.lab_test_result_entries.first(15).map do |entry|
          flag = entry.flag
          "#{entry.analyte&.name}: #{[ entry.value, entry.unit&.name ].compact.join(" ")}#{" (#{flag})" if flag}"
        end
      end

      # What a payment pays for: "appointment #12" (a day by its id, or its
      # series and date while it has none), "supply_purchase #4".
      def about_label(about)
        return unless about
        return "#{about.class.name.underscore} ##{about.id}" unless about.is_a?(Occurrence)

        kind = about.event.type.underscore
        about.persisted? ? "#{kind} ##{about.id}" : "#{kind} event_id #{about.event_id} on #{about.date.iso8601}"
      end

      # The cost of a day (a visit's fee, a meal out), for its summary.
      def cost_fields(occurrence)
        cost = occurrence.cost if occurrence.persisted?
        { cost: money(cost), cost_id: cost&.id, cost_status: cost&.status }
      end

      # A collection by the name the user said ("therapy": "B12", typos
      # included), a healthcare one first, because that is what Healthcare
      # calls a therapy.
      def collection_named(profile, name)
        return if name.blank? || !name.is_a?(String)

        scope = Collection.where(id: Collection.accessible_by(profile).select(:id))
        NameMatch.find(scope.in_section(:healthcare), name) || NameMatch.find(scope, name)
      end

      # The recipes a meal's day cooks, by name: its own when it has any, else
      # its series' (a not-yet-saved meal's too).
      def meal_recipe_names(occurrence)
        details = occurrence.details
        lines = details.meal_recipes.reject(&:marked_for_destruction?)
        lines = details.series_row.meal_recipes.reject(&:marked_for_destruction?) if lines.empty? && !details.series?
        lines.filter_map { |meal_recipe| meal_recipe.recipe&.name }
      end

      # What the viewer's pantry can't cover for each of `recipes`, by the
      # recipe's id: "Flour: have 200 g, need 500 g", "Eggs: none in the
      # pantry". A recipe with everything there has no entry.
      def pantry_shortages(recipes, profile)
        return {} if recipes.empty?

        Pantry::Availability.new(profile).for(recipes).select(&:short?).group_by { |line| line.recipe_ingredient.recipe_id }
          .transform_values { |lines| lines.map { |line| shortage_text(line) } }
      end

      def shortage_text(line)
        name = line.recipe_ingredient.ingredient.name
        return "#{name}: none in the pantry" if line.status == :out

        on_hand = [ line.on_hand.to_f.round(3).to_s.delete_suffix(".0"), line.unit&.name ].compact_blank.join(" ")
        needed = [ line.needed.to_f.round(3).to_s.delete_suffix(".0"), line.unit&.name ].compact_blank.join(" ")
        "#{name}: have #{on_hand}, need #{needed}"
      end

      # "Flour: 0.5 kg", or just "Flour" for a grocery item with no quantity
      def pantry_line(line) = [ line.ingredient.name, [ line.quantity&.to_s, line.unit&.name ].compact.join(" ").presence ].compact.join(": ")

      # "pg/mL (any): low 150, high 250, critical below 80 / above 300"
      def range_text(range)
        bounds = [ ("low #{range.low.to_f}" if range.low), ("high #{range.high.to_f}" if range.high),
                   ("critical at/below #{range.critical_low.to_f}" if range.critical_low),
                   ("critical at/above #{range.critical_high.to_f}" if range.critical_high) ].compact
        "#{range.unit.name} (#{range.sex}): #{bounds.join(", ")}"
      end
    end
  end
end
