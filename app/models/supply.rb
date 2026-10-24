# frozen_string_literal: true

class Supply < ApplicationRecord
  include IdempotentlyNamed
  include Searchable

  searchable_by :name

  belongs_to :profile
  names_unique_within :profile_id

  enum :category, { medication: 0, consumable: 1 }

  # What is left of it, and how many times it was bought (preload_stock).
  Stock = Data.define(:purchases, :remaining)

  # A supply a medication plans to use stays until no plan names it.
  # Otherwise it goes with its purchases and everything doses drew from it,
  # the draws first, before deleting a purchase would set them aside. A cost
  # paid for a purchase stays, unattached (Costable).
  has_many :supply_uses, dependent: :restrict_with_error
  has_many :supply_consumptions, dependent: :destroy
  has_many :supply_purchases, dependent: :destroy

  accepts_nested_attributes_for :supply_purchases, reject_if: ->(attrs) { attrs["quantity_purchased"].blank? }

  # Supplies a profile can access: their own, plus any bought for a therapy
  # shared with them (they take doses from that stock — SupplyPurchase.accessible_by).
  scope :accessible_by, ->(profile) {
    where_id_in_any(unscoped.where(profile_id: profile.id).select(:id), SupplyPurchase.accessible_by(profile).select(:supply_id))
  }

  # The supplies a dose can draw from, by name.
  def self.choices_for(profile) = accessible_by(profile).order(:name)

  # What is left and how many times it was bought: read once for many
  # supplies by preload_stock, else asked here.
  def total_remaining
    @stock ? @stock.remaining : supply_purchases.where("quantity_remaining > 0").sum(:quantity_remaining)
  end

  def purchase_count = @stock ? @stock.purchases : supply_purchases.count

  # Many supplies' stock in one query (the supplies list, a month of doses'
  # cards): what is left of each, how often each was bought.
  def self.preload_stock(supplies)
    rows = SupplyPurchase.where(supply_id: supplies.map(&:id)).group(:supply_id)
      .pluck(:supply_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(quantity_remaining) FILTER (WHERE quantity_remaining > 0)"))
      .to_h { |id, purchases, remaining| [ id, Stock.new(purchases: purchases, remaining: remaining || 0) ] }
    supplies.each { |supply| supply.stock = rows.fetch(supply.id) { Stock.new(purchases: 0, remaining: 0) } }
  end

  attr_writer :stock

  def reload(...)
    @stock = nil
    remove_instance_variable(:@daily_rate) if defined?(@daily_rate)
    super
  end

  def low_stock?
    low_stock_threshold.present? && total_remaining <= low_stock_threshold
  end

  def projected_depletion_date
    self.class.depletion_date(remaining: total_remaining, daily_rate: daily_rate)
  end

  # How much of it is used a day (daily_rates): read for many supplies at
  # once by preload_daily_rates, else asked here.
  def daily_rate
    return @daily_rate if defined?(@daily_rate)

    @daily_rate = self.class.daily_rates([ self ])[id]
  end

  attr_writer :daily_rate

  def self.preload_daily_rates(supplies)
    rates = daily_rates(supplies)
    supplies.each { |supply| supply.daily_rate = rates[supply.id] }
  end

  SCHEDULE_WINDOW_DAYS = 90
  HISTORY_WINDOW_DAYS = 30

  def self.depletion_date(remaining:, daily_rate:)
    return nil unless daily_rate&.positive?

    (remaining / daily_rate).ceil.days.from_now.to_date
  end

  # { supply_id => units consumed per day, or nil } for many supplies in a
  # fixed number of queries (the statistics dashboard lists every supply).
  # A supply with a recurring schedule uses the scheduled rate even when it
  # is 0 (the series has ended, so it's not running out). Only supplies
  # with no schedule at all fall back to history.
  def self.daily_rates(supplies)
    ids = supplies.map(&:id)
    scheduled = scheduled_daily_rates(ids)
    historical = SupplyConsumption.where(supply_id: ids, consumed_at: HISTORY_WINDOW_DAYS.days.ago..)
      .group(:supply_id).sum(:quantity)

    ids.index_with do |id|
      next scheduled[id] if scheduled.key?(id)

      recent = historical[id].to_d
      recent.positive? ? recent / HISTORY_WINDOW_DAYS.to_f : nil
    end
  end

  # What the running series plan to use per day over the next window: each
  # recurring Medication's planned uses (SupplyUse on its series' details)
  # times its doses in the window.
  def self.scheduled_daily_rates(supply_ids)
    uses = SupplyUse.joins(medication_details: :event)
      .where(supply_id: supply_ids, medication_details: { occurrence_id: nil })
      .where.not(events: { rrule: nil })
      .pluck(:supply_id, "events.id", :quantity)
    return {} if uses.empty?

    from, to = Date.current, Date.current + SCHEDULE_WINDOW_DAYS
    events = Event.preload_occurrences(Event.where(id: uses.map { |_, event_id, _| event_id }.uniq), from, to).index_by(&:id)
    doses = events.transform_values { |event| event.occurrences_between(from, to).size }

    uses.group_by(&:first).transform_values do |rows|
      rows.sum { |_, event_id, quantity| doses.fetch(event_id, 0) * quantity } / SCHEDULE_WINDOW_DAYS.to_f
    end
  end
  private_class_method :scheduled_daily_rates
end
