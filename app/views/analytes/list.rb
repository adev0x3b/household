# frozen_string_literal: true

# The index's results frame, rendered by the full-page index and on its own
# as the answer to the navbar search (Components::IndexSearch).
class Views::Analytes::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "analytes_results"

  def initialize(analytes:, query: nil)
    @analytes = analytes
    @query = query
  end

  def view_template
    # The frame holds only the results; a card's links open whole pages.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      div(class: "analytes__list") do
        if @analytes.any?
          @analytes.each { |analyte| render Views::Analytes::Card.new(analyte: analyte) }
        else
          render Components::EmptyState.new(icon: "fa-ruler",
                                            message: t(@query.present? ? "analytes.index.empty_search" : "analytes.index.empty"))
        end
      end
      render Components::Pagination.new(collection: @analytes, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end
end
