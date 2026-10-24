# frozen_string_literal: true

# A meal: cooked at home from recipes (the pantry is emptied when it's
# eaten), eaten out or ordered in (with its cost). The Pantry section.
class Meal < Event
  has_details "Meal::Details"

  validates :title, presence: true, unless: -> { details.home? }
  validate :home_meal_has_something_to_cook

  def self.section = :pantry
  def self.fee_category = :dining_out

  # A home meal's card warns when its owner's pantry can't cover it: each
  # owner's pantry read once for all their meals (Pantry::Availability).
  def self.preload_for_cards(days)
    owners = days.map { |day| day.event.profile }.uniq(&:object_id)
    ActiveRecord::Associations::Preloader.new(records: owners, associations: { ingredients: :unit }).call
  end

  # A planned home meal its owner's pantry can't cover yet. Once it is
  # eaten the stock has already been drawn, so it no longer is.
  def short_on?(occurrence)
    return false if occurrence.completed? || !occurrence.details.home?

    Pantry::Availability.new(profile).short?(occurrence.details.resolved_recipes)
  end

  def event_label
    title.presence || details.recipes.map(&:name).to_sentence.presence || self.class.default_title
  end

  # A day with its own recipes is named after them.
  def occurrence_label(occurrence)
    occurrence.own_title.presence || occurrence.own_details&.recipes&.map(&:name)&.to_sentence.presence || event_label
  end

  def cost_title(occurrence)
    I18n.t("meals.form.transaction_title", title: occurrence.event_label, date: I18n.l(occurrence.date, format: :long))
  end

  # A meal out is paid to the place it is named after.
  def cost_counterpart(occurrence) = occurrence.event_label

  # Due at the meal's usual hour (never a time of its own).
  def due_clock(occurrence)
    [ Events::TimesOfDay::MEALS.fetch(occurrence.details.meal_type.to_s, Events::TimesOfDay::MORNING), false ]
  end

  def on_occurrence_completed(occurrence) = Consumption.new(occurrence).record!
  def on_occurrence_uncompleting(occurrence) = Consumption.new(occurrence).reverse!

  def on_occurrences_destroying(days) = Consumption.reverse_all!(days)

  private

  def home_meal_has_something_to_cook
    return unless details.home?
    return if title.present? || details.meal_recipes.reject(&:marked_for_destruction?).any?

    errors.add(:base, :recipes_or_title)
  end
end
