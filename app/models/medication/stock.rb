# frozen_string_literal: true

class Medication
  # What a dose does to the supply cupboard. Taken: each planned use
  # (SupplyUse) leaves the cupboard from the batch expiring first, recorded
  # on the day as a SupplyConsumption. Untaken or deleted: every batch it
  # drew from gets its quantity back.
  class Stock
    def initialize(occurrence)
      @occurrence = occurrence
    end

    # Each use not drawn yet takes from its supply's batch expiring first
    # (FEFO) that has some left, else its newest: a depleted batch goes
    # negative, a visible "you're out", rather than the draw being split.
    # The batches of every use are read at once; each draw is a counter
    # update, so two doses taken at once both count.
    def record!
      uses = @occurrence.details.resolved_uses.reject { |use| @occurrence.supply_consumptions.any? { _1.supply_id == use.supply_id } }
      batches = SupplyPurchase.accessible_by(@occurrence.profile).where(supply_id: uses.map(&:supply_id)).fefo_order.group_by(&:supply_id)
      drawn = uses.filter_map do |use|
        candidates = batches.fetch(use.supply_id, [])
        batch = candidates.find { _1.quantity_remaining.positive? } || candidates.max_by(&:purchased_on) or next

        SupplyPurchase.update_counters(batch.id, quantity_remaining: -use.quantity)
        @occurrence.supply_consumptions.build(supply_id: use.supply_id, supply_purchase: batch, quantity: use.quantity, consumed_at: Time.current)
      end
      SupplyConsumption.read_access(drawn)
      drawn.each(&:save!)
      uses.each { |use| use.supply.stock = nil if use.association(:supply).loaded? } # what is left changed
      @occurrence.supply_consumptions.reset
    end

    def reverse! = self.class.reverse_all!([ @occurrence ])

    # Every batch many doses drew from gets its quantity back, in one read
    # and a counter update per batch (deleting a series' days at once).
    def self.reverse_all!(days)
      days = days.select(&:persisted?)
      consumptions = SupplyConsumption.where(occurrence_id: days.map(&:id)).to_a
      consumptions.group_by(&:supply_purchase_id).each do |purchase_id, drawn|
        SupplyPurchase.update_counters(purchase_id, quantity_remaining: drawn.sum(&:quantity)) if purchase_id
      end
      SupplyConsumption.where(id: consumptions.map(&:id)).delete_all
      days.each { |day| day.supply_consumptions.reset }
    end

    # After the planned uses of a taken dose changed: give back what the
    # old list drew, draw the new one.
    def resync!
      reverse!
      record!
    end
  end
end
