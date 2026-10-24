# frozen_string_literal: true

# An index page whose search sits in the top bar (Components::IndexSearch,
# among the page's controls). The search form targets the page's results
# frame, so a search request answers with that frame alone and the input
# being typed into is never re-rendered.
module SearchableIndex
  # A whole number of rows at one, two, three or four cards across.
  PAGE_SIZE = 24

  private

  def search_query = params[:q].to_s.strip.presence

  # The page of the index the request names. Its sort ends on something
  # unique, so a row never shows on two pages or on none.
  def index_page(scope, param: :page) = scope.paginate(page: params[param], per_page: PAGE_SIZE)

  def render_searchable_index(page:, results:)
    if turbo_frame_request_id == results.class::FRAME_ID
      render results, layout: false
    else
      render_page page
    end
  end
end
