# frozen_string_literal: true

# The expense paid for a day (a visit's fee, a meal out's bill), shown as a
# line inside that day's card instead of as a card of its own (see
# Views::Calendar::DayCard#costs_by_host). It keeps its own paid /
# unpaid toggle: paying is separate from doing.
class Views::Calendar::Cards::AttachedCost < Views::Base
  include Views::Calendar::DayPaths

  # occurrence: the expense's day (a Transaction's Occurrence).
  def initialize(occurrence:, viewer: nil)
    @occurrence = occurrence
    @access = Occurrences::Access.new(occurrence, viewer)
  end

  def view_template
    div(class: "attached-cost attached-cost--#{status}") do
      toggle
      amount
      span(class: "attached-cost__detail") { facts.join(" · ") }
    end
  end

  private

  def status = @occurrence.status
  def details = @occurrence.details

  def toggle
    label = @occurrence.completed? ? t("transactions.attached_cost.mark_unpaid") : t("transactions.attached_cost.mark_paid")
    render Views::Calendar::Cards::Toggle.new(occurrence: @occurrence, block: "attached-cost", access: @access, label: label, title: label)
  end

  def amount
    if @access.allows?(:show?)
      a(
        href: day_form_path(@occurrence),
        class: "attached-cost__amount",
        title: t("transactions.attached_cost.edit"),
        data: { turbo_stream: true }
      ) { money }
    else
      span(class: "attached-cost__amount") { money }
    end
  end

  def money
    Reports::Money.new(cents: details.amount_cents.to_i, currency: details.currency).to_s
  end

  def facts
    [
      (t("transactions.payment_method.#{details.payment_method}") if details.payment_method.present?),
      t("transactions.attached_cost.status.#{status}")
    ].compact
  end
end
