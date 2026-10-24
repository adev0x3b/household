# frozen_string_literal: true

# An analyte's reference range for one sex, in one of the household's
# units: the normal low and high, and the critical bounds if any.
class Views::ReferenceRanges::Modals::Form < Views::Base
  def initialize(reference_range:, url:)
    @reference_range = reference_range
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :medium, section: :healthcare) do |modal|
      modal.modal_header(
        title: modal_title,
        subtitle: @reference_range.analyte&.name,
        icon: "fa-ruler"
      )

      render Components::Form.new(
        record: @reference_range,
        url: @url,
        submit_text: submit_text,
        modal: modal
      ) do |f|
        render_unit_field(f)
        render_sex_field(f)
        render_low_field(f)
        render_high_field(f)
        render_critical_low_field(f)
        render_critical_high_field(f)
      end
    end
  end

  private

  def modal_title
    @reference_range.persisted? ? t("reference_ranges.form.edit_title") : t("reference_ranges.form.new_title")
  end

  def submit_text
    @reference_range.persisted? ? t("reference_ranges.form.update") : t("reference_ranges.form.create")
  end

  def render_unit_field(f)
    form_field(f, :unit_id, label: t("reference_ranges.form.unit_label"), validation_attribute: :unit, select: true) do |field|
      f.select :unit_id, unit_options, { prompt: t("reference_ranges.form.unit_placeholder") }, required: true, aria: field.aria
    end
  end

  def render_sex_field(f)
    form_field(f, :sex, label: t("reference_ranges.form.sex_label"), select: true) do |field|
      f.select :sex, sex_options, {}, required: true, aria: field.aria
    end
  end

  def render_low_field(f)
    form_field(f, :low, label: t("reference_ranges.form.low_label")) do |field|
      f.number_field :low, step: "any", class: "input is-medium", aria: field.aria
    end
  end

  def render_high_field(f)
    form_field(f, :high, label: t("reference_ranges.form.high_label")) do |field|
      f.number_field :high, step: "any", class: "input is-medium", aria: field.aria
    end
  end

  def render_critical_low_field(f)
    form_field(f, :critical_low, label: t("reference_ranges.form.critical_low_label"), help: t("reference_ranges.form.critical_help")) do |field|
      f.number_field :critical_low, step: "any", class: "input is-medium", aria: field.aria
    end
  end

  def render_critical_high_field(f)
    form_field(f, :critical_high, label: t("reference_ranges.form.critical_high_label")) do |field|
      f.number_field :critical_high, step: "any", class: "input is-medium", aria: field.aria
    end
  end

  def unit_options
    Unit.choices_for(@reference_range.analyte.profile)
  end

  def sex_options
    select_options(ReferenceRange.sexes.keys) { |key| t("reference_ranges.sex.#{key}") }
  end
end
