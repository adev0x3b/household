# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A medication: its doses, their times of the day, and the supplies
    # each dose uses (fields "uses"), which may be ones the same set is
    # still buying.
    class Medications < Series
      # A dose on a day its series doesn't fall on is still about that
      # series, so a same-name series this many days around its date counts
      # as one it may repeat.
      SERIES_WINDOW = 31

      # The supplies each dose uses; future doses copy them.
      def supply_uses
        @supply_uses ||= SupplyUses.new(profile, draft.payload["uses"], bought: @supplies_bought)
          .include_dose!(section["title"], section["quantity"], section["unit"])
      end

      def missing_parts
        parts = super
        parts << { "field" => "medication.kind" } if series.details.kind.blank?
        parts << { "field" => "medication.uses", "problem" => supply_uses.problem } if supply_uses.unknown.any?
        parts
      end

      def screen(warnings, acknowledged)
        screening = super
        return screening if screening.refusal || draft.payload["uses"].blank?

        for_series(screening.warnings) || without_medication(screening.warnings, acknowledged) || screening
      end

      # A dose without the supplies it uses draws nothing from stock: worth
      # a word when the user has supplies the model may have left out.
      def notes
        return [] if draft.payload["uses"].present? || !series.details.injection?
        return [] if @supplies_bought.empty? && SupplyPurchase.accessible_by(profile).none?

        [ "no supplies per dose (uses) — if the user said what each dose uses (the medication itself, a syringe, a needle…), pass uses" ]
      end

      def waits_for_purchase? = supply_uses.pending?

      def use_purchases!
        return unless waits_for_purchase?

        supply_uses.pending_pairs!.each { |supply, quantity| series.details.supply_uses.build(supply: supply, quantity: quantity) }
      end

      # "Metformin on 9 October 2026, with breakfast and at 20:00, using
      # Syringes × 1": the doses of its day, and what each uses.
      def label = Resources.with_supplies(with_times(series.title.presence || type_label), supply_use_lines)

      private

      def fill_in(event, _given)
        details = event.details
        details.kind ||= kind_from_words(event)
        supply_uses.pairs.each { |supply, quantity| details.supply_uses.build(supply: supply, quantity: quantity) }
      end

      # No kind said: a site or a shot says injection, a tablet says pill.
      # Nil when the words don't tell, and then it is asked for.
      def kind_from_words(medication)
        details = medication.details
        return "injection" if details.area.present? || details.side.present?

        words = [ medication.title, details.unit ].join(" ").downcase
        return "injection" if words.match?(/inject|shot|syring|vial|\bml\b/)
        return "pill" if words.match?(/pill|tablet|capsule|compress/)

        "drops" if words.match?(/drop|gocc/)
      end

      def series_around(query, date)
        resource.search(profile, query: query, date_from: date - SERIES_WINDOW, date_to: date + SERIES_WINDOW)
          .select { |summary| summary[:repeats].present? }.uniq { |summary| summary[:event_id] }
      end

      # A new medication with the supplies each dose uses, named like one
      # that already repeats ("I forgot the supplies for my injection"). A
      # hint alone may be asked about rather than followed, so the call is
      # refused pointing at the series; the warning stays shown, so
      # confirm: true still creates a separate one.
      def for_series(warnings)
        repeating = warnings.find { |warning| warning["code"] == "possible_duplicate" && warning.dig("existing", "repeats").present? }
        return unless repeating

        id = repeating.dig("existing", "event_id")
        name = repeating.dig("existing", "title")
        Screening.new(warnings: warnings, refusal: taken_from_series?(id) ? taken_refusal(id, name) : series_refusal(id, name))
      end

      # "I just took it, with a needle": that dose is done, with what it
      # used, when the series has a dose that day; else "taken" was the
      # model's guess.
      def taken_from_series?(id)
        day = record.date || Date.current
        requested_status == "completed" && Event.find(id).occurrence_dates_between(day, day).include?(day)
      end

      def taken_refusal(id, name)
        "#{name} already repeats (event_id #{id}): a dose of it taken is marked done — call mark_done with type medication, " \
          "ref \"event_id #{id} on #{(record.date || Date.current).iso8601}\" and the same uses. Only if the user really has a " \
          "second, separate medication, call this again with confirm: true."
      end

      def series_refusal(id, name)
        "#{name} already repeats (event_id #{id}): don't create it again. What each dose uses goes on it with set_dose_supplies " \
          "(medication \"#{name}\", the same uses); new days, a new dose or when it ends with update_record (ref \"event_id #{id}\"). " \
          "Only if the user really has a second, separate medication, call this again with confirm: true."
      end

      # Supplies with no new medication around them: no name at all, or a
      # therapy's name ("B12"), when "for my injection I use…" is filed as a
      # new medication. With a medication that repeats, the supplies are
      # its, so the call says so. confirm: true still creates one.
      def without_medication(warnings, acknowledged)
        name = series.title.to_s.squish
        therapies = Collection.where(id: Collection.accessible_by(profile).select(:id))
        return unless name.empty? || NameMatch.find(therapies, name)

        repeating = Medication.accessible_by(profile).where.not(rrule: nil).to_a
          .select { |event| event.occurrence_dates_between(Date.current, Date.current + Resources::CalendarResource::NEXT_DAY_WITHIN).any? }
        names = repeating.filter_map { |event| event.title.presence }.uniq
        return if names.empty?

        warning = { "code" => "supplies_without_medication", "existing" => { "type" => "medication", "event_id" => repeating.first.id } }
        return if acknowledged.include?(DraftEvaluator.warning_key(warning))

        Screening.new(warnings: warnings + [ warning ],
                      refusal: "no new medication was named#{" (#{name} is a therapy)" if name.present?}: what each dose uses goes on the " \
                               "medication it's for — call set_dose_supplies with medication (#{names.join(" or ")}) and the same uses. " \
                               "Only if the user is adding a new medication, call this again with its name and confirm: true.")
      end

      # "Metformin on 9 October 2026, with breakfast and at 20:00".
      def with_times(text)
        day = record
        return with_date(text, day.date) if !series.timed? || day.date.nil?

        I18n.t("assistant.operations.on_date_at", thing: text, date: I18n.l(day.date, format: :long),
                                                  when: series.slots.map { |time, anchor| Events::TimesOfDay.when_label_for(time, anchor) }.to_sentence)
      end

      # What the dose uses, said or still being bought in this change.
      def supply_use_lines
        supply_uses.pairs.map { |supply, quantity| [ supply.name, quantity, supply.unit_label ] } +
          supply_uses.pending.map { |name, quantity| [ name, quantity, nil ] }
      end
    end
  end
end
