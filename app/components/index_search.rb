# frozen_string_literal: true

# The top-bar search of an index page (SearchableIndex). `results` is the
# page's results view class: the form targets its FRAME_ID, so typing only
# ever refreshes the list below, and keeps `?q=` in the URL. `hidden:` are
# the page's other filters (a status, a scope), sent along so a search
# does not reset them.
class Components::IndexSearch < Components::Base
  def initialize(url:, results:, query:, placeholder:, hidden: {})
    @url = url
    @results = results
    @query = query
    @placeholder = placeholder
    @hidden = hidden
  end

  def view_template
    frame_id = @results::FRAME_ID

    render Components::AutoSubmitForm.new(
      url: @url,
      dom_id: "#{frame_id}_search",
      html_class: "index-search",
      turbo_frame: frame_id,
      turbo_action: "replace"
    ) do |form|
      @hidden.each { |name, value| input(type: "hidden", name: name, value: value) }
      render Components::Icon.new("fa-magnifying-glass", class: "index-search__icon")
      form.search_field(name: "q", value: @query, placeholder: @placeholder, html_class: "index-search__input")
    end
  end
end
