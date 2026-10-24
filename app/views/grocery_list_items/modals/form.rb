# frozen_string_literal: true

# One item's details: how much, in what, and the store section its
# ingredient is found in (which is the ingredient's own, so it moves on
# every list).
class Views::GroceryListItems::Modals::Form < Views::Base
  def initialize(item:)
    @item = item
  end

  def view_template
    render Components::Modal.new(size: :small, section: :pantry) do |modal|
      modal.modal_header(title: t("grocery_list_items.form.title", name: @item.ingredient.name), icon: "fa-cart-shopping")

      render Components::Form.new(record: @item, url: grocery_list_item_path(@item), submit_text: t("grocery_list_items.form.update"), modal: modal) do |f|
        render_quantity_field(f)
        render_unit_field
        render_category_field(f)
      end
    end
  end

  private

  def form_errors = @form_errors ||= Forms::Errors.new(@item)

  def render_quantity_field(f)
    render Components::Field.new(label: t("grocery_list_items.form.quantity_label"), control_id: f.field_id(:quantity),
                                 errors: form_errors.for(:quantity)) do |field|
      f.number_field :quantity, value: number_value(@item.quantity), step: "any", min: "0", class: "input is-medium",
                                placeholder: t("grocery_list_items.form.quantity_placeholder"), aria: field.aria
    end
  end

  # A unit by name, resolved by GroceryListItem#unit_name= against the
  # household's units.
  def render_unit_field
    render Components::Field.new(label: t("grocery_list_items.form.unit_label"), control_id: "grocery_list_item_unit_name",
                                 errors: form_errors.for(:unit)) do |field|
      input(type: "text", id: "grocery_list_item_unit_name", name: "grocery_list_item[unit_name]", value: @item.unit&.name,
            list: Components::UnitsDatalist::ID, class: "input is-medium", placeholder: t("grocery_list_items.form.unit_placeholder"),
            aria: field.aria)
      render Components::UnitsDatalist.new(profile: @item.grocery_list.profile)
    end
  end

  def render_category_field(f)
    render Components::Field.new(label: t("grocery_list_items.form.category_label"), control_id: f.field_id(:category), select: true,
                                 errors: form_errors.for(:category)) do |field|
      f.select :category, select_options(Ingredient.categories.keys) { |key| t("ingredients.category.#{key}") }, {}, aria: field.aria
    end
  end
end
