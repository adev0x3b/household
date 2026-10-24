# frozen_string_literal: true

# Money on a day, as the viewer reads it: the payer sees an expense, the
# housemate it was paid for (the counterparty) the same payment as an
# income — one series, two readers, only the owner changes it
# (TransactionOccurrencePolicy).
class Views::Calendar::Cards::TransactionCard < Views::Calendar::Cards::Base
  def self.icon = "fa-money-bill-wave"

  private

  def prefix = "transaction-card"

  def kind = @event.kind_for(viewer, details)

  def card_classes = super << "transaction-card--#{kind}"

  def amount
    return if details.amount_cents.nil?

    render Components::SignedMoney.new(cents: @event.signed_cents_for(viewer, details), currency: details.currency)
  end

  def content
    div(class: "transaction-card__content") do
      div(class: "transaction-card__header") do
        title_link
        kind_badge if income?
      end

      span(class: "transaction-card__amount") { amount } unless details.amount_cents.nil?
      meta_row
      span(class: "transaction-card__detail") { t("transactions.attached_to", thing: @event.about_label) } if @event.about_label.present?
      span(class: "transaction-card__detail") { counterparty } if counterparty.present?
      outcome
    end
  end

  # The counterparty reads it but can't open its form.
  def title_link
    return span(class: "transaction-card__title") { title } unless access.allows?(:show?)

    super
  end

  # Money coming in is the exception on a calendar, so it is the one kind
  # named: an expense is told by its sign, and most days hold only those.
  def income? = kind == "income"

  def kind_badge
    span(class: "transaction-card__kind") { t("transactions.kind.#{kind}") }
  end

  def meta_row
    category = details.category
    payment_method = details.payment_method
    return if category.blank? && payment_method.blank?

    div(class: "transaction-card__meta") do
      span(class: "transaction-card__meta-item") { t("transactions.category.#{category}") } if category.present?
      span(class: "transaction-card__meta-item") { t("transactions.payment_method.#{payment_method}") } if payment_method.present?
    end
  end

  # Who the money went to or came from — for the counterparty, its owner.
  def counterparty
    return @event.profile.display_name if @event.counterparty?(viewer)

    details.counterparty_display_name
  end
end
