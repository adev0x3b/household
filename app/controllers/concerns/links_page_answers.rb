# frozen_string_literal: true

# How a change to links is answered where it was made, the Links page or
# the bell (LinksController, LinkApprovalsController, LinkGrantsController):
# the page's sections drawn again for the viewer. The other side's copy is
# Links::Broadcaster's.
module LinksPageAnswers
  extend ActiveSupport::Concern

  private

  def links_page = ::Links::Page.new([ current_profile ])

  def redraw_links_sections
    sections = Views::Links::Sections.new(viewer: current_profile, page: links_page)
    turbo_stream.replace(sections.dom_id, sections)
  end

  # The sections and a toast; without Turbo, the Links page with the toast.
  def answer_link_change(type, notice)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: [ redraw_links_sections, toast(type, notice) ] }
      format.html do
        toast_flash(type, notice)
        redirect_to links_path, status: :see_other
      end
    end
  end
end
