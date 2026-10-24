# frozen_string_literal: true

class SupplyPurchase < ApplicationRecord
  include Costable
  include EditedTogether

  belongs_to :supply
  belongs_to :profile
  belongs_to :collection, optional: true

  # A dose taken from this batch keeps what it drew once the batch is
  # deleted, from no batch in particular: a done day is a record.
  has_many :supply_consumptions, dependent: :nullify

  before_validation :default_quantity_remaining, on: :create

  validates :quantity_purchased, presence: true, numericality: { greater_than: 0 }
  # No lower bound here: a taken dose deliberately lets a depleted batch
  # go negative as a visible "you're out" signal rather than splitting
  # consumption across multiple batches (see Medication::Stock#record!).
  validates :quantity_remaining, presence: true, numericality: true
  validates :purchased_on, presence: true
  validates_accessible :supply, by: :profile
  validates_accessible :collection, by: :profile

  # Purchases a profile can access: their own, and those bought for a
  # collection shared with them, as a series in it is.
  scope :accessible_by, ->(profile) {
    where_id_in_any(
      unscoped.where(profile_id: profile.id).select(:id),
      unscoped.where(collection_id: CollectionShare.where(profile_id: profile.id).select(:collection_id)).select(:id)
    )
  }

  # Soonest-expiring first, for FEFO (first-expired-first-out) consumption.
  scope :fefo_order, -> {
    order(Arel.sql("COALESCE(expires_on, opened_on, '9999-12-31') ASC"), purchased_on: :asc)
  }

  def effective_expiration_date
    candidates = [ expires_on ]

    if opened_on.present?
      pao = pao_days_override || supply.pao_days
      candidates << (opened_on + pao.days) if pao.present?
    end

    candidates.compact.min
  end

  def expired?
    effective_expiration_date.present? && Date.current > effective_expiration_date
  end

  # Title of the cost transaction attached to this purchase. "20" rather
  # than "20.0" for a whole-batch quantity, the way a person would say it.
  def cost_title
    quantity = quantity_purchased == quantity_purchased.to_i ? quantity_purchased.to_i.to_s : quantity_purchased.to_s
    I18n.t("supply_purchases.form.transaction_title", quantity: quantity, supply_name: supply.name)
  end

  private

  # Applies uniformly whether this purchase is created through the
  # standalone restock flow or nested under a Supply being created for the
  # first time — neither caller has to remember to set it.
  def default_quantity_remaining
    self.quantity_remaining ||= quantity_purchased
  end
end
