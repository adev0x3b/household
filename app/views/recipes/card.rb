# frozen_string_literal: true

# A recipe in the list: its name, whose it is, and what the viewer may do
# with it. A housemate it is shared with may edit it; only its owner
# shares or deletes it.
class Views::Recipes::Card < Views::Base
  def initialize(recipe:, viewer:)
    @recipe = recipe
    @viewer = viewer
  end

  def view_template
    render Components::Card.new(dom_id: "recipe_#{@recipe.id}") do |card|
      card.header { a(href: recipe_path(@recipe), class: "recipe-card__name") { @recipe.name } }
      card.body { render Views::Shares::Whose.new(thing: @recipe, viewer: @viewer) }
      card.actions { actions }
    end
  end

  private

  def owner?
    @recipe.profile_id == @viewer.id
  end

  def shared?
    @recipe.shared_profiles.include?(@viewer)
  end

  # The name opens the recipe; editing is on the card, sharing and deleting,
  # the owner's, behind "more".
  def actions
    if owner? || shared?
      render Components::ItemAction.new(href: edit_recipe_path(@recipe), icon: "fa-pen", label: t("recipes.card.edit"), turbo_stream: true)
    end
    render Components::ItemMenu.new(label: t("recipes.card.more"), actions: menu_actions)
  end

  def menu_actions
    return [] unless owner?

    [
      Components::Action.new(href: new_recipe_share_path(recipe_id: @recipe.id), icon: "fa-share-nodes", label: t("recipes.card.share"),
                             turbo_stream: true),
      Components::Action.new(href: recipe_path(@recipe), icon: "fa-trash", label: t("recipes.card.destroy"),
                             method: :delete, confirm: t("recipes.confirm_destroy", name: @recipe.name), danger: true)
    ]
  end
end
