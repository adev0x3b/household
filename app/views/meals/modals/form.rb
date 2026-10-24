# frozen_string_literal: true

# A meal's day: cooked at home from recipes, or eaten out / ordered in with
# a name and its cost (meal_form_controller.js shows the fields that apply);
# which meal of the day, how it repeats and — once saved — whether it was
# eaten.
class Views::Meals::Modals::Form < Views::Occurrences::Form
  private

  def form_data = { controller: "meal-form" }

  def fields(f)
    render_title_field(f)
    details_fields(f) do |d|
      render_details_select(d, :kind, "meals.form.kind_label", select_options(Meal::Details.kinds.keys) { |key| t("meals.kind.#{key}") },
                            data: { meal_form_target: "kind", action: "change->meal-form#syncKind" })
      render_details_select(d, :meal_type, "meals.form.meal_type_label", select_options(Meal::Details.meal_types.keys) { |key| t("meals.meal_type.#{key}") },
                            include_blank: t("meals.form.meal_type_blank"), required: false)
    end
    render_recipes_section
    render_text_area(f, :notes, "meals.form.notes_label", placeholder_key: "meals.form.notes_placeholder")
    render_event_fields
    render_collection_picker
    render_cost_section
    render_status_field(f)
  end

  def home? = details.home?

  # Needed for eating out / ordering in (the place), optional for a home meal
  # (it defaults to the recipe names). No `required` attribute: which one
  # applies depends on the kind, so the server validates.
  def render_title_field(f)
    render Components::Field.new(label: t("meals.form.title_label"), control_id: "#{param_key}_title", help: t("meals.form.title_help")) do
      f.text_field :title, class: "input is-medium", placeholder: t("meals.form.title_placeholder"), autofocus: true
    end
  end

  def recipes_prefix(index) = "#{param_key}[details_attributes][meal_recipes_attributes][#{index}]"

  # The recipes of a meal cooked at home.
  def render_recipes_section
    list = ::Occurrences::DetailsList.new(@occurrence, :meal_recipes, key: :recipe_id, prefix: method(:recipes_prefix))

    fieldset(class: "meal-recipes", hidden: !home?, data: { meal_form_target: "homeSection" }) do
      legend(class: "label") { t("meals.form.recipes.label") }
      p(class: "help") { t("meals.form.recipes.help") }
      list.dropped_inputs.each { input(**_1) }

      render Components::NestedFields.new(rows_class: "meal-recipes__rows", row_class: "meal-recipe-row", prefix: method(:recipes_prefix),
                                          add_label: t("meals.form.recipes.add"), remove_label: t("meals.form.recipes.remove"),
                                          errors: form_errors.rows(:"details.meal_recipes")) do |fields|
        fields.rows { list.rows.each { |row| render_recipe_row(fields, row.child, row.index, id_inputs: list.id_inputs(row)) } }
        fields.template { render_recipe_row(fields, MealRecipe.new, Components::NestedFields::NEW_ROW) }
      end
    end
  end

  def render_recipe_row(fields, meal_recipe, index, id_inputs: nil)
    fields.row(record: meal_recipe, index: index, id_inputs: id_inputs) do |prefix, row|
      div(class: "meal-recipe-row__field") do
        div(class: "select is-small is-fullwidth") do
          select(name: "#{prefix}[recipe_id]", aria: { label: t("meals.form.recipes.placeholder"), **row.aria(:recipe, :recipe_id) }) do
            option(value: "") { t("meals.form.recipes.placeholder") }
            recipes.each do |recipe|
              option(value: recipe.id, selected: meal_recipe.recipe_id == recipe.id) { recipe.name }
            end
          end
        end
      end
    end
  end

  def recipes
    @recipes ||= Recipe.choices_for(@current_profile).to_a
  end

  # What a meal eaten out or ordered in cost.
  def render_cost_section
    fieldset(hidden: home?, data: { meal_form_target: "awaySection" }) do
      legend(class: "label") { t("meals.form.cost_section.label") }
      p(class: "help") { t("meals.form.cost_section.help") }

      render Views::Transactions::CostFields.new(cost: @occurrence.cost&.details, currency: @current_profile.household.currency)
    end
  end
end
