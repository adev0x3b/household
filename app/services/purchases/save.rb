# frozen_string_literal: true

module Purchases
  # A purchase saved together with what it cost, or neither: a supply's or
  # an ingredient's purchase, or a new supply with its first one. The cost
  # is the one expense about the purchase (Transactions::SetCost), paid on
  # its date, from the form's few fields (amount, payment method, who was
  # paid). No amount, no cost: on an update an attached cost is left as it
  # is — there is no removing one.
  #
  #   result = Purchases::Save.call(purchase, cost: { amount: "4.50", payment_method: "card" }, category: :groceries) { build_purchase }
  #   result.success?   # false: result.record carries every error, the cost's included
  #
  # A new record that failed comes back built again by the block: a save
  # rolled back still says persisted?, and its form would post to the
  # update URL. An update's record keeps what was typed. The calendar's
  # cards are redrawn once it has all committed.
  class Save
    Result = ServiceResult.define(:record)

    def self.call(...) = new(...).call

    # attributes: what an update changes (nil: the record is saved as
    # built); paying_for: the purchase the cost is about, from the record.
    def initialize(record, cost:, category:, attributes: nil, paying_for: ->(purchase) { purchase }, &rebuild)
      raise ArgumentError, "a new record needs a block that builds it again" if record.new_record? && rebuild.nil?

      @record = record
      @cost = cost.to_h.symbolize_keys
      @category = category
      @attributes = attributes
      @paying_for = paying_for
      @rebuild = rebuild
      @creating = record.new_record?
    end

    def call
      change = nil
      saved = false
      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless @attributes ? @record.update(@attributes) : @record.save

        change = set_cost
        saved = true
      rescue ActiveRecord::RecordInvalid => e
        @cost_errors = e.record.errors
        raise ActiveRecord::Rollback
      end
      return failed unless saved

      Calendar::DayCardBroadcaster.call(event: change.cost.event, dates: Array(change.moved_from)) if change
      Result.new(record: @record, error: nil)
    end

    private

    def set_cost
      return if @cost[:amount].blank?

      purchase = @paying_for.call(@record) or return
      Transactions::SetCost.call(
        purchase, date: purchase.purchased_on, title: purchase.cost_title, category: @category,
                  status: :completed, # a purchase is logged once bought, so it's paid
                  amount: @cost[:amount], payment_method: @cost[:payment_method],
                  counterpart_mode: @cost[:counterparty_mode].presence || "text", counterpart: @cost[:counterparty],
                  counterparty_profile_id: @cost[:counterparty_profile_id]
      )
    end

    def failed
      record = @creating ? @rebuild.call : @record
      if @cost_errors
        # The expense's errors are added as whole sentences: imported under
        # their attributes, they would read as the purchase's.
        @cost_errors.each { |error| record.errors.add(:base, error.full_message) }
      elsif @creating
        record.valid?
      end
      Result.new(record: record, error: :invalid)
    end
  end
end
