# frozen_string_literal: true

# An analyte's reference ranges, from its page: the modal that adds one
# under the analyte or corrects one by its own id, and deleting one.
class ReferenceRangesController < ApplicationController
  before_action :set_analyte, only: %i[new create]
  before_action :set_reference_range, only: %i[edit update destroy]

  def new
    @reference_range = @analyte.reference_ranges.build
    authorize @reference_range

    render_modal(form_view(@reference_range, analyte_reference_ranges_path(@analyte)), page: @analyte)
  end

  def edit
    authorize @reference_range
    render_modal(form_view(@reference_range, reference_range_path(@reference_range)), page: @reference_range.analyte)
  end

  def create
    @reference_range = @analyte.reference_ranges.new(reference_range_params)
    authorize @reference_range

    if @reference_range.save
      redirect_back_after_save(analyte_path(@analyte), notice: t("reference_ranges.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@reference_range, analyte_reference_ranges_path(@analyte))), status: :unprocessable_content
    end
  end

  def update
    authorize @reference_range

    if @reference_range.update(reference_range_params)
      redirect_back_after_save(analyte_path(@reference_range.analyte), notice: t("reference_ranges.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@reference_range, reference_range_path(@reference_range))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @reference_range
    @reference_range.destroy!

    redirect_back_after_save(analyte_path(@reference_range.analyte), notice: t("reference_ranges.notices.destroyed"))
  end

  private

  def set_analyte
    @analyte = policy_scope(Analyte).find(params[:analyte_id])
  end

  def set_reference_range
    @reference_range = ReferenceRange.where(analyte: policy_scope(Analyte)).find(params[:id])
  end

  def reference_range_params
    params.expect(reference_range: %i[unit_id sex low high critical_low critical_high])
  end

  def form_view(reference_range, url)
    Views::ReferenceRanges::Modals::Form.new(reference_range: reference_range, url: url)
  end
end
