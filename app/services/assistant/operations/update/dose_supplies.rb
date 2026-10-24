# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # What each dose of a medication uses from now on, written on the
      # series' row so every dose without a list of its own follows it.
      # Taken doses keep what they really drew, except a one-off dose
      # already taken, whose stock follows its new list.
      class DoseSupplies < Part
        def initialize(record, raw, changes:, context:)
          super(record, profile: context.profile)
          @raw = raw
          @changes = changes
          @context = context
        end

        def series_level? = true

        def check
          uses = SupplyUses.new(profile, @raw, bought: @context.supplies_bought)
          fail!(uses.problem) if uses.unknown.any?
          details = record.details
          uses.include_dose!(@changes.fetch("title", record.title), @changes.fetch("quantity", details.quantity), @changes.fetch("unit", details.unit))
          fail!("uses is empty") unless uses.any?
          @uses = uses
        end

        def checked? = @uses.present?

        # One of them is still being bought in this set: the dose can't be
        # saved before that purchase is.
        def waits_for_purchase? = checked? && @uses.pending?

        def apply!(applier)
          list = @uses.list!
          event = record.event
          Pundit.authorize(profile, record, record.persisted? ? :update? : :edit?)
          before = event.details.uses_list
          event.details.replace_uses!(list)
          extra = {}
          unless event.recurring?
            own = record.persisted? ? record.own_details : nil
            if own&.supply_uses&.any?
              extra[:day_before] = own.uses_list
              own.replace_uses!(list)
            end
            if record.persisted? && record.completed?
              Medication::Stock.new(record).resync!
              extra[:resync] = true
            end
            extra[:day_id] = record.id if extra.any?
          end
          applier.defer([ -> { Calendar::DayCardBroadcaster.call(event: event) } ])
          [ entry("uses", event, before: before, **extra) ]
        end

        # Only the supplies change: what the user sees is the series' next dose.
        def apply_alone!(applier)
          entries = apply!(applier)
          applier.saved([ summarize(record) ])
          entries
        end

        # "Update the supplies of Cobalamin from 5 October 2026 on, using …",
        # or the dose on its day when its fields change too.
        def label(text, date, only_supplies:)
          thing = if only_supplies && record.event.recurring?
            I18n.t("assistant.operations.supplies_from", thing: text, date: I18n.l(uses_from, format: :long))
          else
            I18n.t("assistant.operations.on_date", thing: text, date: I18n.l(date, format: :long))
          end
          lines = @uses.pairs.map { |supply, quantity| [ supply.name, quantity, supply.unit_label ] } +
                  @uses.pending.map { |name, quantity| [ name, quantity, nil ] }
          Resources.with_supplies(thing, lines)
        end

        private

        # The first day a series' new supplies are for.
        def uses_from = record.completed? ? [ record.date + 1, Date.current ].max : record.date
      end
    end
  end
end
