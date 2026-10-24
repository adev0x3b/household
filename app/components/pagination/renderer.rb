# frozen_string_literal: true

require "will_paginate/view_helpers/action_view"

# will_paginate's links in the app's own markup, which `_pagination.scss`
# styles. `link_attributes:` (the frame and action Components::Pagination
# hands in) goes on every page link, and `list:` into the <nav>'s name;
# will_paginate knows neither option and would print both on the <nav>.
class Components::Pagination::Renderer < WillPaginate::ActionView::LinkRenderer
  ARROWS = { "previous" => "fa-chevron-left", "next" => "fa-chevron-right" }.freeze

  def container_attributes
    super.except(:link_attributes, :list)
  end

  protected

  def link(text, target, attributes = {})
    super(text, target, attributes.merge(link_data))
  end

  def html_container(html)
    tag(:nav, html, container_attributes.merge(class: "pagination", "aria-label": aria_label))
  end

  def page_number(page)
    label = page_aria_label(page)
    if page == current_page
      tag(
        :span,
        page,
        class: "pagination__link is-current",
        "aria-label" => label,
        "aria-current" => "page"
      )
    else
      link(page, page, class: "pagination__link", "aria-label" => label, rel: rel_value(page))
    end
  end

  def gap
    tag(:span, gap_text, class: "pagination__gap", "aria-hidden" => "true")
  end

  def previous_page
    num = @collection.current_page > 1 && (@collection.current_page - 1)
    previous_or_next_page(num, @options[:previous_label], "previous_page", I18n.t("pagination.previous"))
  end

  def next_page
    num = @collection.current_page < total_pages && (@collection.current_page + 1)
    previous_or_next_page(num, @options[:next_label], "next_page", I18n.t("pagination.next"))
  end

  # An arrow and the word, which the stylesheet drops on a phone, where
  # the word pushed Next onto a line of its own under the page numbers.
  def previous_or_next_page(page, text, classname, aria_label = nil)
    direction = classname.delete_suffix("_page")
    classes = [ "pagination__link", "pagination__link--#{direction}" ]
    content = arrow_and_word(direction, text)
    if page
      link(content, page, class: classes.join(" "), "aria-label" => aria_label)
    else
      # No page that way: a link that can't be followed, said so to
      # assistive technology (and so exempt from contrast, as inactive).
      classes << "is-disabled"
      tag(:span, content, class: classes.join(" "), role: "link", "aria-disabled" => "true", "aria-label" => aria_label)
    end
  end

  private

  def arrow_and_word(direction, text)
    arrow = @template.render(Components::Icon.new(ARROWS.fetch(direction), class: "pagination__arrow"))
    "#{arrow}#{tag(:span, text, class: "pagination__word")}"
  end

  def link_data
    @options[:link_attributes].to_h.fetch(:data, {}).to_h { |key, value| [ "data-#{key.to_s.dasherize}", value ] }
  end

  def aria_label
    @options[:list] ? I18n.t("pagination.aria_label_of", list: @options[:list]) : I18n.t("pagination.aria_label")
  end

  def page_aria_label(page)
    I18n.t("pagination.page", page: page.to_i)
  end

  def gap_text
    I18n.t("pagination.gap")
  end
end
