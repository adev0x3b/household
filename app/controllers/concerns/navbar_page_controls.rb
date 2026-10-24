# frozen_string_literal: true

# A page names itself, for the browser tab, and brings its own top-bar
# controls (Views::Base#page_title and Views::Base#navbar_controls);
# `render_page` hands both to the layout and renders the page, with any
# options `render` takes (a status).
module NavbarPageControls
  private

  def render_page(view, **)
    @page_title = view.page_title
    @navbar_page_controls = view.navbar_controls
    render(view, **)
  end
end
