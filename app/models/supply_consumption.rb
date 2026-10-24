# frozen_string_literal: true

# What a taken dose really drew from the cupboard: a batch (SupplyPurchase)
# and how much, on the day it was taken. The plan of what a dose uses is a
# SupplyUse on the series' details.
class SupplyConsumption < ApplicationRecord
  belongs_to :supply
  belongs_to :supply_purchase, optional: true
  belongs_to :occurrence, inverse_of: :supply_consumptions

  before_validation :default_consumed_at

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :consumed_at, presence: true
  validates_accessible :supply, by: -> { occurrence&.event&.profile }

  private

  def default_consumed_at
    self.consumed_at ||= Time.current
  end
end
