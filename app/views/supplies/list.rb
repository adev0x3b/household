# frozen_string_literal: true

# The index's results frame, rendered by the full-page index and on its own
# as the answer to the navbar search (Components::IndexSearch).
class Views::Supplies::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "supplies_results"

  def initialize(supplies:, viewer:, query: nil)
    @supplies = supplies
    @viewer = viewer
    @query = query
  end

  def view_template
    # The frame holds only the results; a card's links open whole pages.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      div(class: "supplies__list") do
        if @supplies.any?
          @supplies.each { |supply| render Views::Supplies::Card.new(supply: supply, viewer: @viewer) }
        else
          render Components::EmptyState.new(icon: "fa-box-open",
                                            message: t(@query.present? ? "supplies.index.empty_search" : "supplies.index.empty"))
        end
      end
      render Components::Pagination.new(collection: @supplies, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end
end
