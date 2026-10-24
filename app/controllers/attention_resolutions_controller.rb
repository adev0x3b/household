# frozen_string_literal: true

# "Needs attention" settled from the list itself: one series' days still to
# do marked skipped (`event_id`), or every series the page's list offers to
# settle at once (the page's section in the address, as the page has it,
# and the member picked there; neither names the overview's). Answers back
# to the page, which draws itself again without them.
class AttentionResolutionsController < ApplicationController
  without_authorization "every day is checked by Attention::Resolve with its own policy, whoever calls it", only: :create

  def create
    days = Attention::Resolve.call(series, by: current_profile)
    return refuse(t("statistics.attention.notices.nothing")) if days.empty?

    key = params[:event_id].present? ? "resolved" : "resolved_all"
    redirect_back_after_save(root_path, notice: t("statistics.attention.notices.#{key}"))
  end

  private

  def series
    return [ Event.accessible_by(current_profile).find(params[:event_id]) ] if params[:event_id].present?

    attention.select(&:resolvable).map { |item| item.occurrence.event }.uniq
  end

  # The list the press was on: the overview's, or a section page's for the
  # member picked there.
  def attention
    audience = Reports::Audience.new(viewer: current_profile, member_id: params[:member_id])
    return Reports::Home.overview(audience: audience).attention if params[:section].blank?

    page = Views::Home::Pages::SECTIONS.fetch(params[:section]) { raise ActionController::RoutingError, "unknown page" }
    page.dashboard(Reports::Home.new(audience: audience)).attention
  end
end
