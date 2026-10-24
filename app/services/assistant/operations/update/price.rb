# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # The price of a visit, a meal out or a purchase. It lives on the
      # record's attached payment (Transactions::SetCost), so "the dentist
      # was 80" changes that payment and keeps who it was paid to.
      class Price < Part
        def initialize(record, cost, profile:, name:)
          super(record, profile: profile)
          @cost = cost
          @name = name
        end

        def check
          @cost["amount"] = Normalize.amount(@cost["amount"]) if @cost.key?("amount")
          @cost["payment_method"] = Normalize.enum(@cost["payment_method"]) if @cost.key?("payment_method")
          fail!("#{@name} has no price yet — give amount too") if !@cost.key?("amount") && current_cost.nil?
          problems << "a home meal has no price of its own — only a meal out or ordered in does" if day? && record.details.try(:home?)
        end

        def apply!(applier)
          cost = current_cost
          Pundit.authorize(profile, cost, :update?) if cost
          before = cost && { before: snapshot(cost, DAY_COLUMNS), series_before: snapshot(cost.event, SERIES_COLUMNS + [ "starts_on" ]),
                             series_details_before: details_snapshot(cost.event.details) }
          series = cost&.event
          # A visit's fee is paid with the visit; a purchase was paid when bought.
          paid = record.respond_to?(:completed?) ? record.completed? : true
          saved = Transactions::SetCost.call(
            record, date: day? ? record.date : record.purchased_on, title: cost_title,
                    amount: @cost.fetch("amount") { series.details.amount }, payment_method: @cost.fetch("payment_method") { series&.details&.payment_method },
                    status: paid ? :completed : :pending, category: cost_category,
                    counterpart_mode: series&.details&.counterparty_mode || "text", counterpart: series ? series.details.counterparty : counterpart,
                    counterparty_profile_id: series&.details&.counterparty_profile_id
          ).cost
          applier.defer([ -> { Calendar::DayCardBroadcaster.call(event: saved.event) } ])
          cost ? [ entry("updated", saved, **before) ] : [ entry("created", saved) ]
        end

        private

        # The payment attached to the record (a visit's fee, a purchase's cost).
        def current_cost = record.persisted? ? record.costs.first : nil

        def cost_title = day? ? record.event.cost_title(record) : record.cost_title

        def cost_category
          return record.event.fee_category if day?

          record.try(:cost_category) || :healthcare
        end

        # Who a new payment goes to when nothing says: the kind's answer.
        def counterpart = day? ? record.event.cost_counterpart(record) : nil
      end
    end
  end
end
