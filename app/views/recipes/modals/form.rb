# frozen_string_literal: true

# A recipe: its name and description, its steps in order, and its
# ingredient lines.
class Views::Recipes::Modals::Form < Views::Base
  def initialize(recipe:, url:)
    @recipe = recipe
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :large, section: :pantry) do |modal|
      modal.modal_header(
        title: modal_title,
        subtitle: modal_subtitle,
        icon: "fa-book-open"
      )

      render Components::Form.new(
        record: @recipe,
        url: @url,
        submit_text: submit_text,
        modal: modal
      ) do |f|
        render_name_field(f)
        render_description_field(f)
        render_steps_section
        render_ingredients_section
      end
    end
  end

  private

  def modal_title
    @recipe.persisted? ? t("recipes.form.edit_title") : t("recipes.form.new_title")
  end

  def modal_subtitle
    t("recipes.form.new_subtitle") unless @recipe.persisted?
  end

  def submit_text
    @recipe.persisted? ? t("recipes.form.update") : t("recipes.form.create")
  end

  def render_name_field(f)
    form_field(f, :name, label: t("recipes.form.name_label")) do |field|
      f.text_field :name,
                   class: "input is-medium",
                   placeholder: t("recipes.form.name_placeholder"),
                   autofocus: true,
                   required: required_attribute?(@recipe, :name), aria: field.aria
    end
  end

  def render_description_field(f)
    form_field(f, :description, label: t("recipes.form.description_label")) do |field|
      f.text_area :description,
                  class: "textarea",
                  placeholder: t("recipes.form.description_placeholder"),
                  required: required_attribute?(@recipe, :description), aria: field.aria
    end
  end

  # The steps, in order, one plain-text row each, added and removed in place.

  def render_steps_section
    fieldset(class: "recipe-steps-field") do
      legend(class: "label") { t("recipes.form.steps.label") }

      render Components::NestedFields.new(rows_class: "recipe-steps-field__rows", row_class: "recipe-step-row", prefix: method(:step_field_prefix),
                                          add_label: t("recipes.form.steps.add"), remove_label: t("recipes.form.steps.remove"),
                                          errors: form_errors.rows(:recipe_steps)) do |fields|
        fields.rows { existing_steps.each { |step| render_step_row(fields, step, fields.index_of(step)) } }
        fields.template { render_step_row(fields, RecipeStep.new, Components::NestedFields::NEW_ROW) }
      end
    end
  end

  def existing_steps
    steps = @recipe.recipe_steps.sort_by(&:position)
    steps.any? ? steps : [ @recipe.recipe_steps.build ]
  end

  def render_step_row(fields, step, index)
    fields.row(record: step, index: index) do |prefix, row|
      div(class: "recipe-step-row__field") do
        textarea(
          name: "#{prefix}[instruction]",
          class: "textarea is-small",
          placeholder: t("recipes.form.steps.placeholder"),
          aria: { label: t("recipes.form.steps.step_label"), **row.aria(:instruction) }
        ) { plain step.instruction }
      end
    end
  end

  def form_errors = @form_errors ||= Forms::Errors.new(@recipe)

  def step_field_prefix(index)
    "recipe[recipe_steps_attributes][#{index}]"
  end

  # The ingredient lines: a name (the pantry's, or a new one made on save), a
  # quantity and a unit, added and removed in place.

  def render_ingredients_section
    fieldset(class: "recipe-ingredients-field") do
      legend(class: "label") { t("recipes.form.ingredients.label") }
      render_datalists

      render Components::NestedFields.new(rows_class: "recipe-ingredients-field__rows", row_class: "recipe-ingredient-row", prefix: method(:ingredient_field_prefix),
                                          add_label: t("recipes.form.ingredients.add"), remove_label: t("recipes.form.ingredients.remove"),
                                          errors: form_errors.rows(:recipe_ingredients)) do |fields|
        fields.headings([ t("recipes.form.ingredients.ingredient_label"), "recipe-ingredient-row__field" ],
                        [ t("recipes.form.ingredients.quantity_label"), "recipe-ingredient-row__field recipe-ingredient-row__field--quantity" ],
                        [ t("recipes.form.ingredients.unit_label"), "recipe-ingredient-row__field recipe-ingredient-row__field--unit" ])
        fields.rows { existing_ingredients.each { |entry| render_ingredient_row(fields, entry, fields.index_of(entry)) } }
        fields.template { render_ingredient_row(fields, RecipeIngredient.new, Components::NestedFields::NEW_ROW) }
      end
    end
  end

  # Rendered once (not per-row) — every ingredient/unit input references
  # these by id via `list:`, letting the user pick a suggestion or type a
  # new name either way.
  def render_datalists
    datalist(id: "ingredients-datalist") { Ingredient.names_for(@recipe.profile).each { |name| option(value: name) } }
    render Components::UnitsDatalist.new(profile: @recipe.profile)
  end

  def existing_ingredients
    entries = @recipe.recipe_ingredients
    entries.any? ? entries : [ @recipe.recipe_ingredients.build ]
  end

  def render_ingredient_row(fields, entry, index)
    fields.row(record: entry, index: index) do |prefix, row|
      div(class: "recipe-ingredient-row__field") do
        input(
          type: "text",
          name: "#{prefix}[ingredient_name]",
          value: entry.ingredient&.name,
          list: "ingredients-datalist",
          class: "input is-small",
          placeholder: t("recipes.form.ingredients.ingredient_placeholder"),
          aria: { label: t("recipes.form.ingredients.ingredient_label"), **row.aria(:ingredient, :ingredient_id) }
        )
      end

      div(class: "recipe-ingredient-row__field recipe-ingredient-row__field--quantity") do
        input(
          type: "number",
          name: "#{prefix}[quantity]",
          value: number_value(entry.quantity),
          step: "any",
          min: "0",
          class: "input is-small",
          placeholder: t("recipes.form.ingredients.quantity_placeholder"),
          aria: { label: t("recipes.form.ingredients.quantity_label"), **row.aria(:quantity) }
        )
      end

      div(class: "recipe-ingredient-row__field recipe-ingredient-row__field--unit") do
        input(
          type: "text",
          name: "#{prefix}[unit_name]",
          value: entry.unit&.name,
          list: Components::UnitsDatalist::ID,
          class: "input is-small",
          placeholder: t("recipes.form.ingredients.unit_placeholder"),
          aria: { label: t("recipes.form.ingredients.unit_label"), **row.aria(:unit) }
        )
      end
    end
  end

  def ingredient_field_prefix(index)
    "recipe[recipe_ingredients_attributes][#{index}]"
  end
end
