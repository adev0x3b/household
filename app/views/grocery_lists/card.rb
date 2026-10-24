# frozen_string_literal: true

# One grocery list on the index: how far along it is, whose it is,
# and its own actions. Replaced alone for everyone it is shared with when it
# changes (GroceryLists::Broadcaster).
class Views::GroceryLists::Card < Views::Base
  def self.dom_id(grocery_list) = "grocery_list_#{grocery_list.id}"

  def initialize(grocery_list:, viewer:)
    @grocery_list = grocery_list
    @viewer = viewer
  end

  def view_template
    render Components::Card.new(dom_id: self.class.dom_id(@grocery_list)) do |card|
      card.header { header_content }
      card.body { body_content }
      card.actions { actions }
    end
  end

  private

  def owner?
    @grocery_list.profile_id == @viewer.id
  end

  def header_content
    a(href: grocery_list_path(@grocery_list), class: "grocery-list-card__name") { @grocery_list.name }
    render Views::GroceryLists::StatusBadge.new(status: @grocery_list.status)
  end

  def body_content
    progress_line
    render Views::Shares::Whose.new(thing: @grocery_list, viewer: @viewer)
  end

  def progress_line
    progress = Views::GroceryLists::Progress.new(grocery_list: @grocery_list)
    p(class: "grocery-list-card__progress") { progress.text }
    render progress
  end

  # The name opens the list; renaming is on the card, sharing, shopping again
  # and deleting behind "more".
  def actions
    render Components::ItemAction.new(href: edit_grocery_list_path(@grocery_list), icon: "fa-pen", label: t("grocery_lists.card.rename"), turbo_stream: true)
    render Components::ItemMenu.new(label: t("grocery_lists.card.more"), actions: menu_actions)
  end

  def menu_actions
    actions = []
    if owner?
      actions << Components::Action.new(href: new_grocery_list_share_path(grocery_list_id: @grocery_list.id), icon: "fa-share-nodes",
                                        label: t("grocery_lists.card.share"), turbo_stream: true)
    end
    if @grocery_list.completed?
      actions << Components::Action.new(href: grocery_list_completion_path(@grocery_list), icon: "fa-rotate-left", label: t("grocery_lists.card.shop_again"),
                                        method: :delete, confirm: t("grocery_lists.confirm_reopen", name: @grocery_list.name))
    end
    if owner?
      actions << Components::Action.new(href: grocery_list_path(@grocery_list), icon: "fa-trash", label: t("grocery_lists.card.destroy"),
                                        method: :delete, confirm: t("grocery_lists.confirm_destroy", name: @grocery_list.name), danger: true)
    end
    actions
  end
end
