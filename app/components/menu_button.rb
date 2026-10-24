# frozen_string_literal: true

# The round "more" button that opens a menu of an item's actions: its own,
# beside it (Components::ItemMenu), or one drawn once for a page of items
# and filled for the item pressed (a calendar card's). Says it opens a menu
# and whether that menu is open; `data:` wires it to whichever opens it.
#
#   render Components::MenuButton.new(label: t("books.card.more"), controls: Views::Calendar::CardMenu::ID,
#                                     data: Views::Calendar::CardMenu.opener_data(repeats: true, delete_url: day_path(day)))
class Components::MenuButton < Components::Base
  # controls: the id of the menu it opens, where that menu isn't beside it.
  def initialize(label:, data:, controls: nil, button_class: "item-action")
    @label = label
    @data = data
    @controls = controls
    @button_class = button_class
  end

  def view_template
    button(type: "button", class: [ @button_class, "item-menu__button" ], title: @label,
           aria: { label: @label, expanded: "false", controls: @controls }, data: @data) do
      render Components::Icon.new("fa-ellipsis")
    end
  end
end
