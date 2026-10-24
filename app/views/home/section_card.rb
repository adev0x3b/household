# frozen_string_literal: true

# One section of the household on the overview: its headline figure and a
# line saying what it is. The whole card opens the section's page.
class Views::Home::SectionCard < Views::Base
  def initialize(title:, icon:, href:, value:, caption:, note: nil, section: nil)
    @title = title
    @icon = icon
    @href = href
    @value = value
    @caption = caption
    @note = note
    @section = section
  end

  def view_template
    a(href: @href, class: [ "home-section-card", ("section--#{@section}" if @section) ]) do
      span(class: "home-section-card__header") do
        render Components::Icon.new(@icon, class: "home-section-card__icon")
        span(class: "home-section-card__title") { @title }
        render Components::Icon.new("fa-chevron-right", class: "home-section-card__chevron")
      end
      span(class: "home-section-card__value") { @value }
      span(class: "home-section-card__caption") { @caption }
      span(class: "home-section-card__note") { @note } if @note
    end
  end
end
