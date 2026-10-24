# frozen_string_literal: true

# A link's acceptance, given by the one asked, from the bell or the Links
# page (Links::Accept).
class LinkAcceptancesController < ApplicationController
  include LinksPageAnswers

  def create
    link = Link.involving(current_profile).includes(:requester, :addressee).find(params[:link_id])
    authorize link, :accept?
    Links::Accept.call(link)
    answer_link_change(:success, t("links.notices.accepted", name: link.requester.display_name))
  end
end
