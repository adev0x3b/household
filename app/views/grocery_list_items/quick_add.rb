# frozen_string_literal: true

# The list's quick-add bar: one line, "2 kg flour", Enter. The server reads it
# (GroceryLists::ParseItem) and answers with the list's regions; this form is
# not one of them, so the input keeps focus and quick_add_controller.js only
# clears it on success. The owner's ingredients are offered as suggestions.
class Views::GroceryListItems::QuickAdd < Views::Base
  include Phlex::Rails::Helpers::FormWith

  DATALIST_ID = "grocery-list-ingredients"

  def initialize(grocery_list:)
    @grocery_list = grocery_list
  end

  def view_template
    form_with(
      url: grocery_list_grocery_list_items_path(@grocery_list), method: :post, class: "grocery-list-quick-add",
      data: { controller: "quick-add", action: "turbo:submit-end->quick-add#reset" }
    ) do
      input(
        type: "text", name: "grocery_list_item[text]", list: DATALIST_ID, autocomplete: "off", enterkeyhint: "done", required: true,
        class: "input grocery-list-quick-add__input",
        placeholder: t("grocery_list_items.quick_add.placeholder"),
        aria: { label: t("grocery_list_items.quick_add.label") },
        data: { quick_add_target: "input" }
      )
      button(type: "submit", class: "item-action grocery-list-quick-add__submit",
             aria: { label: t("grocery_list_items.quick_add.submit") }, title: t("grocery_list_items.quick_add.submit")) do
        render Components::Icon.new("fa-plus")
      end
      datalist(id: DATALIST_ID) do
        Ingredient.names_for(@grocery_list.profile).each { |name| option(value: name) }
      end
    end
  end
end
