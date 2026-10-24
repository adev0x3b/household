# frozen_string_literal: true

# One item on the list. The whole row is the thing to tap: it ticks the item
# off (or puts it back) through GroceryListItemChecksController, which
# re-renders the list's items region so the row moves between its section
# and the basket. Editing and removing are the row's own buttons.
class Views::GroceryListItems::Row < Views::Base
  # The row's tick, named the same each time the list is drawn: unticked
  # from the basket, the row comes back to its section and keeps the focus.
  def self.check_id(item) = "grocery_list_item_#{item.id}_check"

  # focus_fallback: the ids, in order, of what takes the focus when the row
  # leaves where it was (ticked into the folded basket, or removed).
  def initialize(item:, focus_fallback: nil)
    @item = item
    @focus_fallback = focus_fallback
  end

  def view_template
    li(id: "grocery_list_item_#{@item.id}", class: [ "grocery-list-item-row", ("grocery-list-item-row--checked" if @item.checked?) ]) do
      a(
        id: self.class.check_id(@item),
        href: grocery_list_item_check_path(@item),
        class: "grocery-list-item-row__main",
        data: { turbo_method: @item.checked? ? :delete : :post, turbo_stream: true, focus_fallback: @focus_fallback },
        aria: { label: toggle_label }
      ) do
        span(class: "grocery-list-item-row__check") { render Components::Icon.new("fa-check") if @item.checked? }
        span(class: "grocery-list-item-row__name") { @item.ingredient.name }
        if @item.quantity
          whitespace
          span(class: "grocery-list-item-row__amount") { quantity_with_unit(@item.quantity, @item.unit) }
        end
      end

      div(class: "grocery-list-item-row__actions") do
        render Components::ItemAction.new(href: edit_grocery_list_item_path(@item), icon: "fa-pen", label: t("grocery_list_items.edit"), turbo_stream: true)
        render Components::ItemAction.new(href: grocery_list_item_path(@item), icon: "fa-trash", label: t("grocery_list_items.destroy"),
                                          turbo_stream: true, method: :delete, danger: true, data: { focus_fallback: @focus_fallback })
      end
    end
  end

  private

  # Names the item as the row shows it, amount and all: a voice command
  # says what it sees ("Flour 2 kg"), and the name must hold it.
  def toggle_label
    item = [ @item.ingredient.name, (quantity_with_unit(@item.quantity, @item.unit) if @item.quantity) ].compact.join(" ")
    @item.checked? ? t("grocery_list_items.uncheck", item: item) : t("grocery_list_items.check", item: item)
  end
end
