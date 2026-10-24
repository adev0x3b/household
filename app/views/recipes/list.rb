# frozen_string_literal: true

# The index's results frame, rendered by the full-page index and on its own
# as the answer to the navbar search (Components::IndexSearch).
class Views::Recipes::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "recipes_results"

  def initialize(recipes:, viewer:, query: nil)
    @recipes = recipes
    @viewer = viewer
    @query = query
  end

  def view_template
    # The frame holds only the results; a card's links open whole pages.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      div(class: "recipes__list") do
        if @recipes.any?
          @recipes.each do |recipe|
            render Views::Recipes::Card.new(recipe: recipe, viewer: @viewer)
          end
        else
          render Components::EmptyState.new(icon: "fa-book-open",
                                            message: t(@query.present? ? "recipes.index.empty_search" : "recipes.index.empty"))
        end
      end
      render Components::Pagination.new(collection: @recipes, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end
end
