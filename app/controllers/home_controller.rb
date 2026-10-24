# frozen_string_literal: true

# The home dashboard: what's going on in the household, and its statistics.
# An overview at "/" (always as of today) and one page per section of the
# household (Views::Home::Pages) at /home/<section>, where the period
# (?start_date=&end_date=, the last 30 days unless one is picked) and the
# member (?member_id=) can be chosen. #show renders a page's shell right
# away; each of its reports is a lazy turbo frame loaded from #report, so
# the heavier ones never hold up the first paint. See
# docs/architecture/dashboards.md.
class HomeController < ApplicationController
  without_authorization "the viewer's own dashboard: every report reads through Reports::Audience (Event.accessible_by and its kin)", only: %i[show report]

  def show
    # A page of the overview's next 7 days: its frame alone.
    if params[:section].nil? && turbo_frame_request_id == Views::Home::AgendaList::FRAME
      return render Views::Home::AgendaList.new(upcoming: home.upcoming), layout: false
    end

    render_page page.new(home: home, pages: list_pages)
  end

  def report
    view = page.report(params[:name]) || raise(ActionController::RoutingError, "unknown report")

    render view.new(home: home), layout: false
  end

  private

  # The overview at "/", else the page named in the address; a name no page has is not found.
  def page
    return Views::Home::Pages::OVERVIEW unless params[:section]

    Views::Home::Pages::SECTIONS.fetch(params[:section]) { raise ActionController::RoutingError, "unknown page" }
  end

  # Which page each of the page's paged lists is on.
  def list_pages = params.permit(*Views::Home::Base::LIST_PAGES).to_h.symbolize_keys.transform_values(&:to_i)

  # The reports the page reads. The overview is always everyone's, as of
  # today: nothing to pick there.
  def home
    unless params[:section]
      return @home ||= Reports::Home.overview(
        audience: Reports::Audience.new(viewer: current_profile), upcoming_page: params[:upcoming_page] || 1,
      )
    end

    @home ||= Reports::Home.new(
      audience: Reports::Audience.new(viewer: current_profile, member_id: params[:member_id]), period: period,
    )
  end

  def period
    return nil if params[:start_date].blank? && params[:end_date].blank?

    Reports::Period.parse(params[:start_date], params[:end_date])
  end
end
