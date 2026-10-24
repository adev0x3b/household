# frozen_string_literal: true

# The housemates one sees calendars with (/links): what waits for an
# answer, then each link with what each side lets the other do, then the
# housemates one could link with. Everything below the title is
# Views::Links::Sections, redrawn whole after each change (and live, by
# Links::Broadcaster, when the other side changes something).
class Views::Links::Index < Views::Base
  def initialize(viewer:, page:)
    @viewer = viewer
    @page = page
  end

  def page_title = t("links.index.title")

  def view_template
    div(class: "report-page links section--links") do
      render Components::PageHeader.new(title: t("links.index.title"))
      p(class: "report-hint") { t("links.index.hint") }
      render Views::Links::Sections.new(viewer: @viewer, page: @page)
    end
  end
end
