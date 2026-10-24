# frozen_string_literal: true

# A page's title, the one place it is shown: the h1, with the way back
# when the page has a parent, a line under it when it has one to say, and
# beside it whatever the block renders (a status). Never holds actions:
# those are the top bar's (Components::PageControls).
#
#   render Components::PageHeader.new(title: @trip.name, back_href: trips_path, back_label: t("trips.show.back"))
class Components::PageHeader < Components::Base
  def initialize(title:, subtitle: nil, back_href: nil, back_label: nil)
    @title = title
    @subtitle = subtitle
    @back_href = back_href
    @back_label = back_label
  end

  def view_template(&block)
    header(class: "page-header") do
      if @back_href
        a(href: @back_href, class: "page-header__back", aria: { label: @back_label }, title: @back_label) do
          render Components::Icon.new("fa-arrow-left")
        end
      end
      div(class: "page-header__text") do
        div(class: "page-header__line") do
          h1(class: "page-title") { @title }
          yield if block
        end
        p(class: "page-header__subtitle") { @subtitle } if @subtitle.present?
      end
    end
  end
end
