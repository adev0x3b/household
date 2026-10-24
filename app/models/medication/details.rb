# frozen_string_literal: true

class Medication
  class Details < ::Details::Base
    self.table_name = "medication_details"

    enum :kind, { injection: 0, pill: 1, drops: 2 }
    enum :area, { thigh: 0, glute: 1, arm: 2 }
    enum :side, { left: 0, right: 1 }

    has_many :supply_uses, foreign_key: :medication_details_id, dependent: :destroy, inverse_of: :medication_details
    has_many :supplies, through: :supply_uses
    accepts_nested_attributes_for :supply_uses, allow_destroy: true,
                                                reject_if: ->(attrs) { attrs["supply_id"].blank? || attrs["quantity"].blank? }
    reads_access_of :supply_uses

    def self.recorded = %i[kind area side quantity unit pill_count]
    def self.opposite_side(side) = side.to_s == "left" ? :right : :left

    # A dose is read with what it plans to use.
    def self.preloads = [ { supply_uses: :supply } ]
    def self.lists = %i[supply_uses]

    inherits :kind, :area, :side, :quantity, :unit, :pill_count
    series_requires :kind
    validates :area, :side, presence: true, if: -> { series? && injection? }

    # What a dose is planned to use: its own list when it has one, else the
    # series'.
    def resolved_uses
      own = supply_uses.reject(&:marked_for_destruction?)
      return own if series? || own.any?

      series_row.supply_uses.to_a
    end

    # Whether a supply the dose uses is running low.
    def low_on_supplies? = resolved_uses.any? { |use| use.supply.low_stock? }

    # [[supply_id, "quantity"], …] — what replace_uses! takes back.
    def uses_list = resolved_uses.map { |use| [ use.supply_id, use.quantity.to_s ] }

    def replace_uses!(uses)
      supply_uses.reset
      transaction do
        supply_uses.destroy_all
        added = uses.map { |supply_id, quantity| supply_uses.build(supply_id: supply_id, quantity: quantity) }
        SupplyUse.read_access(added)
        added.each(&:save!)
      end
      supply_uses.reset
    end

    # The dose as it reads: "0.5 ml".
    def dose_label = [ quantity&.to_s, unit ].compact_blank.join(" ").presence
  end
end
