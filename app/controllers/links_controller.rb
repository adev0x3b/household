# frozen_string_literal: true

# /links — linking with housemates (Links::Request / Decline / Unlink;
# accepting is LinkAcceptancesController); who may do what is LinkPolicy.
# Every change redraws the page's sections (Views::Links::Sections) — and
# the other side's, live.
class LinksController < ApplicationController
  include LinksPageAnswers

  without_authorization "the viewer's own links page: Links::Page reads their links and housemates", only: :index

  rate_limit_per_person to: 20, within: 1.hour, only: :create

  def index
    render_page Views::Links::Index.new(viewer: current_profile, page: links_page)
  end

  def create
    addressee = current_profile.housemates.find(params[:profile_id])
    authorize Link.new(requester: current_profile, addressee: addressee)
    link = Links::Request.call(from: current_profile, to: addressee)
    done(link.accepted? ? t("links.notices.accepted", name: addressee.display_name) : t("links.notices.requested", name: addressee.display_name))
  end

  # Either side ends a link. What that is called depends on where it stood:
  # an accepted link is unlinked; one still waiting is declined by the one
  # asked, or taken back by the asker.
  def destroy
    link = Link.involving(current_profile).includes(:requester, :addressee).find(params[:id])
    authorize link
    partner = link.partner_of(current_profile)

    if link.accepted?
      Links::Unlink.call(link, by: current_profile)
      done(t("links.notices.unlinked", name: partner.display_name))
    else
      Links::Decline.call(link, by: current_profile)
      done(t(link.addressee_id == current_profile.id ? "links.notices.declined" : "links.notices.cancelled", name: partner.display_name))
    end
  end

  private

  def done(notice) = answer_link_change(:success, notice)
end
