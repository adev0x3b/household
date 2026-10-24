# frozen_string_literal: true

# Sharing a thing with a housemate, or no longer: one controller for every
# kind of Shareable, behind the routes' `shareable` concern, which names the
# kind, so sharing works and reads the same whatever is shared.
# The thing is found among what the person can see (404 otherwise) and only
# its owner may go on (SharePolicy). After a share or an unshare the modal
# is drawn again in place, and so is the list of people on the thing's page.
class SharesController < ApplicationController
  THINGS = %w[Event Collection Recipe GroceryList Book Bookshelf Upload].freeze

  before_action :set_thing

  def new
    render_modal(modal, page: @thing)
  end

  def create
    housemate = @thing.share_candidates.find_by(id: params.dig(:share, :profile_id))
    return refuse(t("shares.errors.pick_someone")) unless housemate

    result = Shares::Create.call(@thing, with: housemate, by: current_profile)
    return refuse(result.share.errors.full_messages.to_sentence) if result.failure?

    redraw(t("shares.notices.shared", name: housemate.display_name))
  end

  def destroy
    share = Shares::Destroy.call(@thing.shares.find(params[:id]), by: current_profile)
    redraw(t("shares.notices.unshared", name: share.profile.display_name))
  end

  private

  def set_thing
    @thing = find_thing
    authorize @thing, :share?, policy_class: SharePolicy
    preload_shares
  end

  def find_thing
    type = params[:shareable].presence_in(THINGS) or raise ActiveRecord::RecordNotFound
    return current_profile.bookshelf! if type == "Bookshelf"

    type.constantize.accessible_by(current_profile).find(params[:"#{type.underscore}_id"])
  end

  # Who has it, with their names, for the modal and the list.
  def preload_shares
    ActiveRecord::Associations::Preloader.new(records: [ @thing ], associations: { @thing.share_association => :profile }).call
  end

  def modal = Views::Shares::Modal.new(thing: @thing, candidates: @thing.share_candidates.by_name.to_a)

  def redraw(notice)
    @thing.shares.reset
    preload_shares
    render turbo_stream: [
      turbo_stream.replace(Views::Shares::Modal.dom_id(@thing), modal),
      turbo_stream.replace(Views::Shares::List.dom_id(@thing, :page), Views::Shares::List.new(thing: @thing, place: :page)),
      toast(:success, notice)
    ]
  end
end
