# frozen_string_literal: true

# The list page's top: title and the way back, status, how far the shop is
# and who it is shared with. Replaced as one unit by every change
# (GroceryListStreams, GroceryLists::Broadcaster).
class Views::GroceryLists::Header < Views::Base
  def self.dom_id(grocery_list) = "grocery_list-#{grocery_list.id}-header"

  def initialize(grocery_list:, viewer:)
    @grocery_list = grocery_list
    @viewer = viewer
  end

  def view_template
    div(id: self.class.dom_id(@grocery_list), class: "grocery-list-show__header") do
      render Components::PageHeader.new(title: @grocery_list.name, back_href: grocery_lists_path, back_label: t("grocery_lists.show.back"))

      div(class: "grocery-list-show__meta") do
        render Views::GroceryLists::StatusBadge.new(status: @grocery_list.status)
        p(class: "grocery-list-show__progress") { progress.text }
      end
      render progress

      shared_line
    end
  end

  private

  def progress
    @progress ||= Views::GroceryLists::Progress.new(grocery_list: @grocery_list)
  end

  # The owner sees who they shared it with; a housemate sees whose it is.
  def shared_line
    if @grocery_list.profile_id == @viewer.id
      names = @grocery_list.shared_profiles.map(&:full_name)
      return if names.empty?

      text = t("grocery_lists.show.shared_with", names: names.to_sentence)
    else
      text = t("grocery_lists.show.shared_by", name: @grocery_list.profile.full_name)
    end

    p(class: "grocery-list-show__shared") do
      render Components::Icon.new("fa-user-group")
      span { text }
    end
  end
end
