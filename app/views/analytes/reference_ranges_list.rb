# frozen_string_literal: true

# An analyte's reference ranges on its page, with the button that adds one.
class Views::Analytes::ReferenceRangesList < Views::Base
  def initialize(analyte:, ranges:)
    @analyte = analyte
    @ranges = ranges
  end

  def view_template
    div(class: "reference-ranges") do
      section_header
      body
    end
  end

  private

  def section_header
    div(class: "reference-ranges__header") do
      h2(class: "reference-ranges__title") { t("analytes.show.ranges_title") }

      render Components::AddRowButton.new(
        label: t("reference_ranges.form.add"), href: new_analyte_reference_range_path(@analyte), data: { turbo_stream: true }
      )
    end
  end

  def body
    if @ranges.any?
      div(class: "reference-ranges__list") { @ranges.each { |range| render_range_row(range) } }
    else
      render Components::EmptyState.new(icon: "fa-ruler", message: t("analytes.show.ranges_empty"))
    end
  end

  def render_range_row(range)
    div(class: "reference-range-row") do
      div(class: "reference-range-row__main") do
        span(class: "reference-range-row__sex") { t("reference_ranges.sex.#{range.sex}") }
        span(class: "reference-range-row__unit") { range.unit.name }
        span(class: "reference-range-row__bounds") { bounds_text(range) }
      end

      div(class: "reference-range-row__actions") do
        render Components::ItemAction.new(href: edit_reference_range_path(range), icon: "fa-pen", label: t("reference_ranges.form.edit"),
                                          turbo_stream: true)
        render Components::ItemAction.new(href: reference_range_path(range), icon: "fa-trash", label: t("reference_ranges.form.destroy"),
                                          method: :delete, confirm: t("reference_ranges.confirm_destroy"), danger: true)
      end
    end
  end

  def bounds_text(range)
    parts = []
    parts << "#{t('reference_ranges.form.low_label')} #{format_figure(range.low, :number)}" if range.low
    parts << "#{t('reference_ranges.form.high_label')} #{format_figure(range.high, :number)}" if range.high
    parts << "#{t('reference_ranges.form.critical_low_label')} #{format_figure(range.critical_low, :number)}" if range.critical_low
    parts << "#{t('reference_ranges.form.critical_high_label')} #{format_figure(range.critical_high, :number)}" if range.critical_high
    parts.join(" · ")
  end
end
