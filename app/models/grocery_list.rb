# frozen_string_literal: true

class GroceryList < ApplicationRecord
  include EditedTogether
  include Searchable
  include Shareable

  searchable_by :name

  belongs_to :profile

  shared_through :grocery_list_shares

  # The section of the household it belongs to (the share modal's colour).
  def section = :pantry

  has_many :grocery_list_items, dependent: :destroy, inverse_of: :grocery_list

  enum :status, { active: 0, completed: 1 }

  validates :name, presence: true
  validate :grocery_list_items_have_unique_ingredients

  # The person's own and those shared with them.
  scope :accessible_by, ->(profile) {
    where_id_in_any(unscoped.where(profile_id: profile.id).select(:id), GroceryListShare.where(profile_id: profile.id).select(:grocery_list_id))
  }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  # What a list's card draws: whom it is shared with, and its items for its progress.
  scope :for_cards, -> { includes(:profile, :shared_profiles, :grocery_list_items) }
  # What its page draws: its sharing, and each item's ingredient and unit.
  scope :with_everything, -> { includes(:grocery_list_shares, :shared_profiles, grocery_list_items: [ :ingredient, :unit ]) }

  # Counted on the loaded association (for_cards, with_everything).
  def checked_count = grocery_list_items.count(&:checked?)
  def total_count = grocery_list_items.size
  def all_bought? = total_count.positive? && checked_count == total_count

  # Its items in the order they are shopped, from the loaded association.
  def aisles = GroceryLists::Aisles.new(grocery_list_items)

  # The shop is done.
  def finish! = update!(status: :completed)

  # Puts everything back on the list for the next shop. Unlike
  # GroceryListItem#uncheck!, nothing bought is un-bought: the purchases stay
  # (the stock they added is real), only detached from the items so a later
  # uncheck! can't destroy them.
  def reopen!
    transaction do
      ids = grocery_list_items.where(checked: true).pluck(:id)
      IngredientPurchase.where(grocery_list_item_id: ids).update_all(grocery_list_item_id: nil)
      grocery_list_items.where(id: ids).update_all(checked: false, checked_at: nil)
      update!(status: :active)
    end
  end

  # Shared or no longer (Shareable): the pages open on it follow.
  def on_shared(_share, **) = GroceryLists::Broadcaster.changed(self)
  def on_unshared(_share, **) = GroceryLists::Broadcaster.changed(self)

  private

  def grocery_list_items_have_unique_ingredients
    active = grocery_list_items.reject(&:marked_for_destruction?)
    duplicate_ids = active.filter_map(&:ingredient_id).tally.select { |_, count| count > 1 }.keys
    return if duplicate_ids.empty?

    names = Ingredient.where(id: duplicate_ids).pluck(:name)
    errors.add(:grocery_list_items, :duplicate_ingredients, names: names.join(", "))
  end
end
