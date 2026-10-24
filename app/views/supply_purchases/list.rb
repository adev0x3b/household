# frozen_string_literal: true

# A supply's purchase batches, a page at a time, each row with its own edit
# and delete (SupplyPurchasesController). The frame the top bar's search and
# the page links reload, so the search box is never drawn again.
class Views::SupplyPurchases::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "supply_history_results"

  def initialize(supply:, purchases:)
    @supply = supply
    @purchases = purchases
  end

  def view_template
    turbo_frame_tag(FRAME_ID, class: "supply-history__results") { results }
  end

  private

  def results
    if @purchases.any?
      div(class: "supply-history__list") { @purchases.each { |purchase| purchase_row(purchase) } }
      render Components::Pagination.new(collection: @purchases, turbo_frame: FRAME_ID, turbo_action: "advance")
    else
      render Components::EmptyState.new(icon: "fa-clock-rotate-left", message: t("supplies.history.empty"))
    end
  end

  def purchase_row(purchase)
    div(class: "supply-purchase-row") do
      div(class: "supply-purchase-row__main") do
        span(class: "supply-purchase-row__quantity") do
          t("supplies.history.left_of", left: quantity_with_unit(purchase.quantity_remaining, nil),
                                        bought: quantity_with_unit(purchase.quantity_purchased, @supply.unit_label))
        end
        span(class: "supply-purchase-row__date") { where_and_when(purchase) }
        expiration(purchase)
      end

      div(class: "supply-purchase-row__actions") do
        cost(purchase)
        render Components::ItemAction.new(href: edit_supply_purchase_path(purchase), icon: "fa-pen",
                                          label: t("supply_purchases.form.edit"), turbo_stream: true)
        render Components::ItemAction.new(href: supply_purchase_path(purchase), icon: "fa-trash", label: t("supply_purchases.form.destroy"),
                                          method: :delete, confirm: t("supply_purchases.confirm_destroy"), danger: true)
      end
    end
  end

  # The day, the therapy and the shop: everything the search matches on.
  def where_and_when(purchase)
    [ l(purchase.purchased_on, format: :long), purchase.collection&.name, purchase.cost&.details&.counterparty.presence ].compact.join(" · ")
  end

  # A batch past its date says so in a badge; a good one only when it ends.
  def expiration(purchase)
    date = purchase.effective_expiration_date
    return unless date

    if purchase.expired?
      render Components::StatusBadge.new(tone: :critical, label: t("supplies.history.expired_on", date: l(date, format: :long)))
    else
      span(class: "supply-purchase-row__expiration") { t("supplies.history.expires_on", date: l(date, format: :long)) }
    end
  end

  # Read only: a purchase's cost is changed in its own form.
  def cost(purchase)
    cost = purchase.cost
    return unless cost

    span(class: "supply-purchase-row__cost-label", title: t("supply_purchases.form.cost_section.label")) do
      render Components::Icon.new("fa-receipt")
      whitespace
      plain Reports::Money.new(cents: cost.details.amount_cents, currency: cost.details.currency).to_s
    end
  end
end
