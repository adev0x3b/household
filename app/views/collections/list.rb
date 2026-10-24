# frozen_string_literal: true

# The index's results frame, rendered by the full-page index and on its own
# as the answer to the navbar search (Components::IndexSearch).
class Views::Collections::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "collections_results"

  def initialize(collections:, section:, viewer:, query: nil)
    @collections = collections
    @section = section
    @viewer = viewer
    @query = query
  end

  def view_template
    # The frame holds only the results; a card's links open whole pages.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      div(class: "collections__list") do
        if @collections.any?
          @collections.each do |collection|
            render Views::Collections::Card.new(collection: collection, viewer: @viewer)
          end
        else
          render Components::EmptyState.new(icon: "fa-layer-group",
                                            message: t("collections.sections.#{@section}.index.#{@query.present? ? "empty_search" : "empty"}"))
        end
      end
      render Components::Pagination.new(collection: @collections, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end
end
