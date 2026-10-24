# frozen_string_literal: true

# One recipe: its steps, then its ingredients, each marked when the viewer's
# own pantry is short of it. Editing and sharing it are the top bar's, with
# deleting behind its "more", each for whoever may do it.
class Views::Recipes::Show < Views::Base
  def initialize(recipe:, viewer:, availability: nil)
    @recipe = recipe
    @viewer = viewer
    @availability = availability
  end

  def page_title = @recipe.name

  def navbar_controls
    policy = Pundit.policy!(@viewer, @recipe)
    actions = []
    if policy.update?
      actions << Components::Action.new(href: routes.edit_recipe_path(@recipe), icon: "fa-pen", label: t("recipes.show.edit"), turbo_stream: true)
    end
    if SharePolicy.new(@viewer, @recipe).share?
      actions << Components::Action.new(href: routes.new_recipe_share_path(recipe_id: @recipe.id), icon: "fa-share-nodes",
                                        label: t("recipes.show.share"), turbo_stream: true)
    end
    if policy.destroy?
      actions << Components::Action.new(href: routes.recipe_path(@recipe), icon: "fa-trash", label: t("recipes.show.destroy"), method: :delete,
                                        confirm: t("recipes.confirm_destroy", name: @recipe.name), danger: true)
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(class: "recipe-show") do
      header
      steps_section
      ingredients_section
    end
  end

  private

  def owner? = @recipe.profile_id == @viewer.id

  def header
    render Components::PageHeader.new(title: @recipe.name, subtitle: @recipe.description, back_href: recipes_path, back_label: t("recipes.show.back"))
  end

  def steps_section
    div(class: "recipe-show__steps") do
      h2(class: "recipe-show__section-title") { t("recipes.show.steps_title") }

      steps = @recipe.recipe_steps.sort_by(&:position)

      if steps.any?
        ol(class: "recipe-steps") { steps.each { |step| li(class: "recipe-steps__item") { step.instruction } } }
      else
        render Components::EmptyState.new(icon: "fa-list-ol", message: t("recipes.show.steps_empty"))
      end
    end
  end

  def ingredients_section
    div(class: "recipe-show__ingredients") do
      h2(class: "recipe-show__section-title") { t("recipes.show.ingredients_title") }

      entries = @recipe.recipe_ingredients.sort_by { |ri| ri.ingredient.name }

      if entries.any?
        ul(class: "recipe-ingredients") { entries.each { |entry| render_ingredient_row(entry) } }
        render_pantry_warning
      else
        render Components::EmptyState.new(icon: "fa-carrot", message: t("recipes.show.ingredients_empty"))
      end
    end
  end

  def render_ingredient_row(entry)
    line = lines_by_entry[entry]
    modifier = line&.short? ? " recipe-ingredients__item--#{line.status}" : ""

    li(class: "recipe-ingredients__item#{modifier}") do
      span(class: "recipe-ingredients__name") do
        render Components::Icon.new("fa-triangle-exclamation", class: "recipe-ingredients__warning-icon") if line&.short?
        plain entry.ingredient.name
      end
      span(class: "recipe-ingredients__amount") { quantity_with_unit(entry.quantity, entry.unit) }
    end
  end

  # Judged against the viewer's own pantry, so a shared recipe shows what
  # *they* are missing and reveals nothing of the owner's shelf.
  def lines_by_entry
    @lines_by_entry ||= if @availability
      @availability.for([ @recipe ]).index_by(&:recipe_ingredient)
    else
      {}
    end
  end

  def render_pantry_warning
    short = lines_by_entry.values.select(&:short?).sort_by { |line| line.recipe_ingredient.ingredient.name }
    return if short.empty?

    div(class: "recipe-pantry-warning", role: "status") do
      p(class: "recipe-pantry-warning__title") do
        render Components::Icon.new("fa-triangle-exclamation")
        span { t("recipes.show.pantry_warning.title") }
      end
      ul(class: "recipe-pantry-warning__list") do
        short.each { |line| li { warning_text(line) } }
      end
    end
  end

  def warning_text(line)
    name = line.recipe_ingredient.ingredient.name
    needed = quantity_with_unit(line.needed, line.unit)

    if line.ingredient.nil?
      t("recipes.show.pantry_warning.missing", name: name, needed: needed)
    elsif line.status == :out
      t("recipes.show.pantry_warning.out", name: name, needed: needed)
    else
      t("recipes.show.pantry_warning.low", name: name, needed: needed,
                                           on_hand: quantity_with_unit(line.on_hand, line.unit))
    end
  end
end
