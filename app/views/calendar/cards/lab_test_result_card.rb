# frozen_string_literal: true

# A lab report's day: how many values it holds, a flag when one is out of
# range, and its cost, with a button to add one once the day is saved.
class Views::Calendar::Cards::LabTestResultCard < Views::Calendar::Cards::Base
  def self.icon = "fa-vial"

  private

  def prefix = "lab-test-result-card"

  def entries
    @entries ||= saved? ? @occurrence.lab_test_result_entries.to_a : []
  end

  def content
    div(class: "lab-test-result-card__content") do
      div(class: "lab-test-result-card__header") do
        title_link
        entry_count_badge if entries.any?
        abnormal_icon if abnormal_entry?
      end

      outcome
      attached_costs
    end
  end

  def entry_count_badge
    span(class: "lab-test-result-card__count") { t("lab_test_results.results_count", count: entries.size) }
  end

  # A boolean check across all entries, not per-entry detail — keeps the
  # compact card compact; the full breakdown lives on the edit form.
  def abnormal_entry?
    entries.any? { |entry| entry.flag && entry.flag != :normal }
  end

  def abnormal_icon
    render Components::Icon.new(
      "fa-triangle-exclamation", label: t("lab_test_results.has_abnormal_result"), class: "lab-test-result-card__abnormal-icon"
    )
  end

  # A saved report with no cost yet offers to add one, before the actions
  # every card has.
  def actions
    add_cost_button if saved? && @costs.empty?
    super
  end

  # A cost paid for this report's day: the new payment's form, about it.
  def add_cost_button
    return unless access.allows?(:edit?)

    a(
      href: new_transaction_path(about_type: "Occurrence", about_id: @occurrence.id, date: @occurrence.date.iso8601),
      class: "lab-test-result-card__cost-btn",
      data: { turbo_stream: true },
      title: t("lab_test_results.add_cost")
    ) do
      render Components::Icon.new("fa-receipt")
    end
  end
end
