# frozen_string_literal: true

# A few series shared as one thing — a therapy in Healthcare, a job hunt in
# Agenda — one index per section (`section`, Healthcare when not given),
# worded by it (collections.sections.<section>.*). Its page lists the
# series in it; sharing it shares every one of them (CollectionShare).
class CollectionsController < ApplicationController
  include SearchableIndex
  include KeepsWhatWasTyped

  before_action :set_collection, only: [ :show, :edit, :update, :destroy ]

  def index
    @collections = index_page(policy_scope(Collection).in_section(section).search(search_query).includes(:profile, :shared_profiles).order(:name, :id))

    render_searchable_index(
      page: Views::Collections::Index.new(collections: @collections, section: section, viewer: current_profile, query: search_query),
      results: Views::Collections::List.new(collections: @collections, section: section, viewer: current_profile, query: search_query)
    )
  end

  def show
    authorize @collection

    render_page Views::Collections::Show.new(collection: @collection, viewer: current_profile,
                                             events: Event.preload_first_occurrences(@collection.events.order(:starts_on, :id)))
  end

  def new
    @collection = Collection.new(section: section)
    authorize @collection

    render_modal(form_view(@collection, collections_path), page: collections_path(section: @collection.section))
  end

  def edit
    authorize @collection

    render_modal(form_view(@collection, collection_path(@collection)), page: @collection)
  end

  def create
    @collection = Collection.new(collection_params.merge(profile: current_profile))
    @collection.section = section if @collection.section.blank?
    authorize @collection

    if @collection.save
      redirect_back_after_save(collection_path(@collection), notice: t("collections.sections.#{@collection.section}.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@collection, collections_path)), status: :unprocessable_content
    end
  end

  def update
    authorize @collection

    attributes = collection_params.except(:section)
    if @collection.edit_as(current_profile, typed: typed_fields(@collection, attributes)) { @collection.update(attributes) }
      redirect_back_after_save(collection_path(@collection), notice: t("collections.sections.#{@collection.section}.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@collection, collection_path(@collection))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @collection

    @collection.destroy!

    redirect_after_destroy(collection_path(@collection), list: collections_path(section: @collection.section),
                                                         notice: t("collections.sections.#{@collection.section}.notices.destroyed"))
  end

  private

  # The section an index or a new collection is for; Healthcare by default.
  def section
    params[:section].presence_in(Collection::SECTIONS) ||
      params.dig(:collection, :section).presence_in(Collection::SECTIONS) || "healthcare"
  end

  def set_collection
    @collection = policy_scope(Collection).includes(:collection_shares, :shared_profiles).find(params[:id])
  end

  # The section counts on create only: update leaves it out, so a collection
  # stays in the section it was made in.
  def collection_params
    params.expect(collection: %i[name notes status section lock_version])
  end

  def form_view(collection, url)
    Views::Collections::Modals::Form.new(collection: collection, url: url)
  end
end
