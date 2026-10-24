# frozen_string_literal: true

# The index's results frame, rendered by the full-page index and on its own
# as the answer to the navbar search (Components::IndexSearch).
class Views::Ingredients::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "ingredients_results"

  def initialize(ingredients:, query: nil)
    @ingredients = ingredients
    @query = query
  end

  def view_template
    # The frame holds only the results; a card's links open whole pages.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      div(class: "ingredients__list") do
        if @ingredients.any?
          @ingredients.each { |ingredient| render Views::Ingredients::Card.new(ingredient: ingredient) }
        else
          render Components::EmptyState.new(icon: "fa-carrot",
                                            message: t(@query.present? ? "ingredients.index.empty_search" : "ingredients.index.empty"))
        end
      end
      render Components::Pagination.new(collection: @ingredients, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end
end
