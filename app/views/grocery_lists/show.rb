# frozen_string_literal: true

# One grocery list, as it is shopped: its header, the quick-add bar while it
# is open, and its items. Everyone the list is shared with gets the header
# and items regions pushed over their own signed stream
# (GroceryLists::Broadcaster), so a housemate's ticks show up here live.
# Finishing or reopening it and sharing it are the top bar's, with renaming
# and deleting behind its "more".
class Views::GroceryLists::Show < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  def self.dom_id(grocery_list) = "grocery_list-#{grocery_list.id}-page"

  def initialize(grocery_list:, viewer:)
    @grocery_list = grocery_list
    @viewer = viewer
  end

  def page_title = @grocery_list.name

  # Someone the list is shared with keeps it like its owner does; its owner
  # alone shares and deletes it (GroceryListPolicy, SharePolicy).
  def navbar_controls
    policy = Pundit.policy!(@viewer, @grocery_list)
    actions = []
    actions << (@grocery_list.active? ? finish_action : reopen_action) if policy.update?
    if SharePolicy.new(@viewer, @grocery_list).share?
      actions << Components::Action.new(href: routes.new_grocery_list_share_path(grocery_list_id: @grocery_list.id), icon: "fa-share-nodes",
                                        label: t("grocery_lists.show.share"), turbo_stream: true)
    end
    if policy.update?
      actions << Components::Action.new(href: routes.edit_grocery_list_path(@grocery_list), icon: "fa-pen",
                                        label: t("grocery_lists.show.edit"), turbo_stream: true)
    end
    if policy.destroy?
      actions << Components::Action.new(href: routes.grocery_list_path(@grocery_list), icon: "fa-trash", label: t("grocery_lists.show.destroy"),
                                        method: :delete, confirm: t("grocery_lists.confirm_destroy", name: @grocery_list.name), danger: true)
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(id: self.class.dom_id(@grocery_list), class: "grocery-list-show") do
      turbo_stream_from @grocery_list, @viewer
      render Views::GroceryLists::Header.new(grocery_list: @grocery_list, viewer: @viewer)
      render Views::GroceryListItems::QuickAdd.new(grocery_list: @grocery_list) if @grocery_list.active?
      render Views::GroceryLists::Items.new(grocery_list: @grocery_list)
    end
  end

  private

  def finish_action
    Components::Action.new(href: routes.grocery_list_completion_path(@grocery_list), icon: "fa-flag-checkered",
                           label: t("grocery_lists.show.finish"), method: :post)
  end

  def reopen_action
    Components::Action.new(href: routes.grocery_list_completion_path(@grocery_list), icon: "fa-rotate-left", label: t("grocery_lists.show.shop_again"),
                           method: :delete, confirm: t("grocery_lists.confirm_reopen", name: @grocery_list.name))
  end
end
