# frozen_string_literal: true

# One pill of the Links page's grid: what the viewer lets a linked
# housemate do with one kind of their items (`permission` read / write /
# create / delete, `level` off / ask / on). The housemate hears about it —
# one line under their bell, refreshed while unread — and their calendar
# redraws when a kind of item appears or disappears for them. A kind with
# no grant yet (added to the app after the link was accepted) gets its row
# here, on its owner's first tap.
class LinkGrantsController < ApplicationController
  include LinksPageAnswers

  def update
    link = Link.involving(current_profile).accepted.find(params[:link_id])
    type = params[:event_type].presence_in(LinkGrant::TYPES) or raise ActiveRecord::RecordNotFound
    grant = link.grant_from(current_profile, type)
    authorize grant
    permission = params[:permission].presence_in(LinkGrant::ACTIONS) or return refuse(t("refusals.unknown_choice"))
    level = params[:level].presence_in(LinkGrant.levels_for(permission)) or return refuse(t("refusals.unknown_choice"))

    was_readable = grant.read_on?
    grant.update!("#{permission}_level" => level)
    tell(grant)
    Calendar::Refresh.call(grant.grantee) if was_readable != grant.read_on?

    render turbo_stream: redraw_links_sections
  end

  private

  def tell(grant)
    grantee = grant.grantee
    earlier = grantee.notifications.unread.link_permissions_changed.where(actor: current_profile).order(:id).last
    Notifications::Deliver.call(recipient: grantee, kind: :link_permissions_changed, subject: grant.link, actor: current_profile,
                                title: current_profile.display_name, replace: earlier)
    Links::Broadcaster.changed(grantee)
  end
end
