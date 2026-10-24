# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A purchase of a supply, with what it cost (buying something always
    # costs something), and the supply itself when the user has none by
    # that name yet.
    class SupplyPurchases < DraftBuilder
      # "I use one needle per dose" sent as buying one: a supply already in
      # stock, at most this many, and no price.
      DOSE_SIZED = 2

      # The Supply it is for: one of the profile's (by id, or the one the
      # name clearly means: Assistant::NameMatch, then in another language
      # or form, Lexicon::Matcher, so "needles" bought adds to their "Aghi"),
      # or a new unsaved one of theirs, created when the purchase is saved.
      def supply
        @supply ||= begin
          id = section["supply_id"].presence
          name = section["supply_name"].to_s.squish.presence
          supplies = Supply.where(id: Supply.accessible_by(profile).select(:id))
          if id
            supplies.find_by(id: id)
          elsif name
            NameMatch.find(supplies, name) || Lexicon::Matcher.find(supplies, name) ||
              Supply.new(profile: profile, name: name, category: section["supply_category"].presence_in(Supply.categories.keys) || "consumable",
                         unit_label: section["supply_unit"].presence || "pcs")
          end
        end
      end

      def unresolved = supply ? [] : [ { "field" => "supply_purchase.supply_name" } ]

      # The same supply already bought that day.
      def duplicates
        return [] unless supply&.persisted?

        SupplyPurchase.accessible_by(profile).where(supply: supply, purchased_on: record.purchased_on).map { |purchase| summarize(purchase) }
      end

      # "I'll use 0.12 ml of cobalamin, a syringe and a needle" may be sent
      # as purchases. A supply already in stock, less of it than last bought
      # and no price, while a repeating medication could use it, is most
      # likely what one dose uses. The hint leads the answer
      # (Submit#needs_input_next).
      def warnings(acknowledged)
        series = dose_series
        return [] unless series

        warning = { "code" => "dose_uses", "existing" => { "type" => "medication", "event_id" => series.id, "title" => series.title },
                    "hint" => "#{supply.name} is already in stock. If nothing new was bought and the user is saying what each dose " \
                              "uses (\"I'll use …\"), don't record a purchase: use set_dose_supplies with medication " \
                              "\"#{series.title}\" and uses — EVERY supply they named for one dose." }
        acknowledged.include?(DraftEvaluator.warning_key(warning)) ? [] : [ warning ]
      end

      # A hint alone may be asked about rather than followed, so a
      # dose-sized purchase with it is refused. confirm: true records the
      # purchase anyway.
      def screen(warnings, _acknowledged)
        return super unless warnings.any? { |warning| warning["code"] == "dose_uses" } && record.quantity_purchased.to_d <= DOSE_SIZED

        Screening.new(warnings: warnings,
                      refusal: "#{supply.name} is already in stock and nothing about buying was given (no price): if the user said " \
                               "what each dose USES (\"I use…\", \"1 per dose\"), call set_dose_supplies with the medication and every " \
                               "supply they named. Only if they really bought #{supply.name}, call this again with confirm: true.")
      end

      def form_opens? = supply.present? && supply.persisted?

      def notes
        return [] unless supply

        [ supply.persisted? ? "uses the existing supply #{supply.name}" : "adds the new supply #{supply.name}" ]
      end

      # The supply first when it is new, then the purchase, then what it cost.
      def save!(committer)
        purchase = record
        if supply.new_record?
          Pundit.authorize(profile, supply, :create?)
          supply.save!
          committer.keep(supply)
        end
        purchase.supply = supply
        # A therapy created earlier in this same change set didn't exist when the purchase was built.
        purchase.collection_id ||= Occurrences::Create.accessible_collection_id(profile, collection_id)
        Pundit.authorize(profile, purchase, :create?)
        purchase.save!
        committer.keep(purchase)
        committer.attach_cost(purchase, date: purchase.purchased_on, title: purchase.cost_title, counterparty: cost["counterparty"], status: :completed)
      end

      # "Needles × 100 · €20.00".
      def label
        unit = supply&.unit_label
        quantity = [ record.quantity_purchased.to_s.delete_suffix(".0"), (unit unless unit == "pcs") ].compact_blank.join(" ")
        with_price("#{supply&.name || type_label} × #{quantity}")
      end

      private

      def cost_section = :required

      def own_fields = %w[quantity_purchased purchased_on expires_on opened_on supply_id supply_name supply_unit supply_category collection_id therapy]

      def build
        SupplyPurchase.new(
          section.slice("quantity_purchased", "purchased_on", "expires_on", "opened_on").merge(
            "profile" => profile, "supply" => supply, "collection_id" => Occurrences::Create.accessible_collection_id(profile, collection_id)
          )
        ).tap { |purchase| purchase.purchased_on ||= Date.current }
      end

      # The repeating medication a supply in stock, bought in a dose's
      # quantity and with no price, is most likely for.
      def dose_series
        quantity = record.quantity_purchased
        return unless supply&.persisted? && quantity && cost_attributes["amount"].blank?

        last = SupplyPurchase.accessible_by(profile).where(supply: supply).order(purchased_on: :desc, id: :desc).first
        return unless last && quantity < last.quantity_purchased

        Medication.where(id: Medication.accessible_by(profile).where.not(rrule: nil).select(:id)).order(:starts_on, :id).last
      end
    end
  end
end
