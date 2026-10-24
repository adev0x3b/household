# frozen_string_literal: true

# What a dose is planned to use: a supply and how much of it, on the
# series' details (every dose) or on one day's override (that dose alone).
# What a taken dose really drew is a SupplyConsumption on the day.
class SupplyUse < ApplicationRecord
  include Details::ListItem

  belongs_to :medication_details, class_name: "Medication::Details", inverse_of: :supply_uses
  belongs_to :supply

  list_of :medication_details, as: :supply_uses

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :supply_id, uniqueness: { scope: :medication_details_id }
  validates_accessible :supply, by: -> { medication_details&.event&.profile }
end
