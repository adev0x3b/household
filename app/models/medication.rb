# frozen_string_literal: true

# A medicine taken on a schedule, once or several times a day. What a dose
# is planned to use is drawn from the supply cupboard when the dose is
# taken; an injection alternates sides across the series.
class Medication < Event
  has_details "Medication::Details"

  validates :title, presence: true

  def self.section = :healthcare
  def self.fee_category = :healthcare
  def self.skip_reasons = %w[refused not_available held forgot other]

  # A card warns when a supply its dose uses runs low: every supply each
  # day reads (each its own object), read in one query.
  def self.preload_for_cards(days)
    Supply.preload_stock(days.flat_map { |day| day.details.resolved_uses.map(&:supply) })
  end

  # A dose taken: an injection completed in one tap gets the alternated
  # side, and what it uses leaves the cupboard.
  def on_occurrence_completed(occurrence)
    assign_side!(occurrence)
    Stock.new(occurrence).record!
  end

  def on_occurrence_uncompleting(occurrence) = Stock.new(occurrence).reverse!

  # A deleted dose never happened: give its drawn-down batches back.
  def on_occurrences_destroying(days) = Stock.reverse_all!(days)

  # The side a projected dose would be injected in.
  def projected_side_for(occurrence) = alternation.side_on(occurrence)

  # An injection's continuation starts on the side the old series would
  # have reached that day, so the alternation goes on.
  def continuation(starts_on:)
    super.tap do |copy|
      copy.details.side = projected_side_for(occurrence_on(starts_on, time: first_slot.first)) if details.injection? && recurring?
    end
  end

  # Swaps a dose's planned uses ([[supply_id, quantity], …]) for its own
  # list: a dose not taken yet just gets the list (stock moves when it's
  # taken); a taken one gives back what the old list drew and draws the new.
  def replace_uses_for!(occurrence, uses)
    occurrence.write_details!({})
    occurrence.own_details.replace_uses!(uses)
    Stock.new(occurrence).resync! if occurrence.completed?
  end

  private

  def alternation = @alternation ||= Alternation.new(self)

  def assign_side!(occurrence)
    return unless details.injection? && occurrence.own_details.nil?

    side = projected_side_for(occurrence)
    occurrence.write_details!(side: side) if side.to_s != details.side.to_s
  end
end
