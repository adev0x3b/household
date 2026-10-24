# frozen_string_literal: true

# The analytes lab results are read against: the index, an analyte's page
# with its reference ranges, and the modal that names one.
class AnalytesController < ApplicationController
  include SearchableIndex

  before_action :set_analyte, only: [ :edit, :update, :destroy ]

  def index
    @query = search_query
    @analytes = index_page(policy_scope(Analyte).search(@query).includes(reference_ranges: :unit).order(:name, :id))

    render_searchable_index(page: Views::Analytes::Index.new(analytes: @analytes, query: @query),
                            results: Views::Analytes::List.new(analytes: @analytes, query: @query))
  end

  def show
    @analyte = policy_scope(Analyte).find(params[:id])
    authorize @analyte

    render_page Views::Analytes::Show.new(analyte: @analyte, ranges: @analyte.reference_ranges.includes(:unit).by_sex, viewer: current_profile)
  end

  def new
    @analyte = current_profile.analytes.new
    authorize @analyte

    render_modal(form_view(@analyte, analytes_path), page: analytes_path)
  end

  def edit
    authorize @analyte
    render_modal(form_view(@analyte, analyte_path(@analyte)), page: @analyte)
  end

  def create
    @analyte = current_profile.analytes.new(analyte_params)
    authorize @analyte

    if @analyte.save
      redirect_back_after_save(analyte_path(@analyte), notice: t("analytes.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@analyte, analytes_path)), status: :unprocessable_content
    end
  end

  def update
    authorize @analyte

    if @analyte.update(analyte_params)
      redirect_back_after_save(analyte_path(@analyte), notice: t("analytes.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@analyte, analyte_path(@analyte))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @analyte

    if @analyte.destroy
      redirect_after_destroy(analyte_path(@analyte), list: analytes_path, notice: t("analytes.notices.destroyed"))
    else
      refuse(t("analytes.notices.in_use", name: @analyte.name))
    end
  end

  private

  def set_analyte
    @analyte = policy_scope(Analyte).find(params[:id])
  end

  def analyte_params
    params.expect(analyte: [ :name ])
  end

  def form_view(analyte, url)
    Views::Analytes::Modals::Form.new(analyte: analyte, url: url)
  end
end
