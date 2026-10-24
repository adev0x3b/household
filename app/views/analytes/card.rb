# frozen_string_literal: true

class Views::Analytes::Card < Views::Base
  def initialize(analyte:)
    @analyte = analyte
  end

  def view_template
    render Components::Card.new(dom_id: "analyte_#{@analyte.id}") do |card|
      card.header { a(href: analyte_path(@analyte), class: "analyte-card__name") { @analyte.name } }
      card.body { ranges_section }
      card.actions { actions }
    end
  end

  private

  def ranges_section
    ranges = @analyte.reference_ranges.sort_by(&:sex)

    if ranges.any?
      div(class: "analyte-card__ranges") { ranges.each { |range| range_row(range) } }
    else
      render Components::EmptyState.new(icon: "fa-ruler", message: t("analytes.card.ranges_empty"))
    end
  end

  def range_row(range)
    div(class: "analyte-card__range") do
      span(class: "analyte-card__range-sex") { t("reference_ranges.sex.#{range.sex}") }
      span(class: "analyte-card__range-bounds") { bounds_text(range) }
    end
  end

  def bounds_text(range)
    parts = []
    parts << "#{t('reference_ranges.form.low_label')} #{range.low}" if range.low
    parts << "#{t('reference_ranges.form.high_label')} #{range.high}" if range.high
    "#{range.unit.name} · #{parts.join(' · ')}"
  end

  # The name opens the analyte; editing is on the card, deleting behind "more".
  def actions
    render Components::ItemAction.new(href: edit_analyte_path(@analyte), icon: "fa-pen", label: t("analytes.card.edit"), turbo_stream: true)
    render Components::ItemMenu.new(label: t("analytes.card.more"), actions: [ destroy_action ])
  end

  def destroy_action
    Components::Action.new(href: analyte_path(@analyte), icon: "fa-trash", label: t("analytes.card.destroy"),
                           method: :delete, confirm: t("analytes.confirm_destroy"), danger: true)
  end
end
