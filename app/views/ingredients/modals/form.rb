# frozen_string_literal: true

# An ingredient in the pantry: its name, how much is on hand and in what
# unit, and the store section a grocery list files it under.
class Views::Ingredients::Modals::Form < Views::Base
  def initialize(ingredient:, url:)
    @ingredient = ingredient
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :small, section: :pantry) do |modal|
      modal.modal_header(
        title: modal_title,
        icon: "fa-carrot"
      )

      render Components::Form.new(
        record: @ingredient,
        url: @url,
        submit_text: submit_text,
        modal: modal
      ) do |f|
        render_name_field(f)
        render_quantity_field(f)
        render_unit_field
        render_category_field(f)
      end
    end
  end

  private

  def modal_title
    @ingredient.persisted? ? t("ingredients.form.edit_title") : t("ingredients.form.new_title")
  end

  def submit_text
    @ingredient.persisted? ? t("ingredients.form.update") : t("ingredients.form.create")
  end

  def render_name_field(f)
    form_field(f, :name, label: t("ingredients.form.name_label")) do |field|
      f.text_field :name,
                   class: "input is-medium",
                   placeholder: t("ingredients.form.name_placeholder"),
                   autofocus: true,
                   required: required_attribute?(@ingredient, :name), aria: field.aria
    end
  end

  def render_quantity_field(f)
    form_field(f, :quantity, label: t("ingredients.form.quantity_label")) do |field|
      f.number_field :quantity,
                     value: number_value(@ingredient.quantity),
                     step: "any",
                     min: "0",
                     class: "input is-medium",
                     required: required_attribute?(@ingredient, :quantity), aria: field.aria
    end
  end

  # A unit by name (Ingredient#unit_name=, a TypedName): one of the
  # household's, or a new one made when the ingredient is saved — as a
  # recipe's line and a grocery list's item name theirs.
  def render_unit_field
    render Components::Field.new(label: t("ingredients.form.unit_label"), control_id: "ingredient_unit_name") do
      input(
        type: "text",
        id: "ingredient_unit_name",
        name: "ingredient[unit_name]",
        value: @ingredient.unit&.name,
        list: Components::UnitsDatalist::ID,
        class: "input is-medium",
        placeholder: t("ingredients.form.unit_placeholder")
      )
      render Components::UnitsDatalist.new(profile: @ingredient.profile)
    end
  end

  # Where it is found in the shop: a grocery list is walked section by section.
  def render_category_field(f)
    render Components::Field.new(label: t("ingredients.form.category_label"), control_id: f.field_id(:category), select: true) do
      f.select :category, select_options(Ingredient.categories.keys) { |key| t("ingredients.category.#{key}") }, {}
    end
  end
end
