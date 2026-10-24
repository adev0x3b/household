# frozen_string_literal: true

# A dose: the medication's kind, name, when in the day (a series taken at
# set times), where an injection goes, how much, and on today's dose a
# warning when what it uses is running low. A skipped dose says why.
class Views::Calendar::Cards::MedicationCard < Views::Calendar::Cards::Base
  KIND_ICONS = {
    "injection" => "fa-syringe",
    "pill" => "fa-pills",
    "drops" => "fa-droplet"
  }.freeze

  def self.icon = "fa-pills"

  private

  def prefix = "medication-card"
  def link_class = "medication-card__name-link"

  def kind = details.kind
  def area = details.area
  def injection? = kind == "injection"

  # The side of a saved dose, or the side a projected one would alternate to.
  def side
    saved? ? details.side : @event.projected_side_for(@occurrence).to_s
  end

  def content
    div(class: "medication-card__content") do
      div(class: "medication-card__header") do
        kind_icon if kind.present?
        title_link
        time_badge if @occurrence.time_label
        position_badge if injection? && area.present? && side.present?
        low_stock_icon if low_stock_today?
      end

      quantity_label if quantity_text
      outcome
      attached_costs
    end
  end

  def kind_icon
    render Components::Icon.new(KIND_ICONS.fetch(kind, "fa-pills"), class: "medication-card__kind-icon")
  end

  def time_badge
    span(class: "medication-card__time") do
      render Components::Icon.new("fa-clock", style: :regular)
      whitespace
      plain @occurrence.time_label
    end
  end

  def position_badge
    span(class: "medication-card__position") { t("medications.position.#{area}.#{side}") }
  end

  # What this dose is planned to use (its own list, else the series').
  def uses
    @uses ||= details.resolved_uses
  end

  # A medication is taken for months, and a warning on every one of its
  # days would drown the one that matters: today's, where the next dose
  # is taken. Home's "needs attention" names the supply itself.
  def low_stock_today?
    @occurrence.date == Date.current && details.low_on_supplies?
  end

  def low_stock_icon
    render Components::Icon.new(
      "fa-triangle-exclamation", label: t("medications.low_stock_warning"), class: "medication-card__low-stock-icon"
    )
  end

  # The dose ("0.5 ml"), else how much of the drug itself it uses — the
  # supply filed as a medication, as opposed to a syringe or a wipe.
  def quantity_text
    return @quantity_text if defined?(@quantity_text)

    drug = uses.find { |use| use.supply.medication? }
    @quantity_text = (quantity_with_unit(details.quantity, details.unit) if details.dose_label) ||
                     (quantity_with_unit(drug.quantity, drug.supply.unit_label) if drug)
  end

  def quantity_label
    span(class: "medication-card__quantity") { quantity_text }
  end

  def status_text
    reason = @occurrence.skipped_reason
    return super unless saved? && reason.present?

    "#{super} · #{t("medications.skipped_reason.#{reason}")}"
  end
end
