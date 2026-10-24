# frozen_string_literal: true

class Views::Supplies::Card < Views::Base
  def initialize(supply:, viewer:)
    @supply = supply
    @viewer = viewer
  end

  def view_template
    render Components::Card.new(dom_id: "supply_#{@supply.id}") do |card|
      card.header { header_content }
      card.body { stock_info }
      card.actions { actions }
    end
  end

  private

  def header_content
    span(class: "supply-card__name") { @supply.name }
    span(class: "supply-card__category") { t("supplies.category.#{@supply.category}") }
  end

  def stock_info
    p(class: "supply-card__remaining") { quantity_with_unit(@supply.total_remaining, @supply.unit_label) }
    stock_flag
  end

  def stock_flag
    if @supply.low_stock?
      render Components::StatusBadge.new(tone: :warning, label: t("supplies.index.low_stock"))
    elsif (date = @supply.projected_depletion_date)
      p(class: "supply-card__projection") { t("supplies.card.projected_depletion", date: l(date, format: :long)) }
    end
  end

  # Its history and buying more on the card; changing it, the owner's, behind "more".
  def actions
    render Components::ItemAction.new(href: supply_purchases_path(@supply), icon: "fa-clock-rotate-left", label: t("supplies.card.history"))
    render Components::ItemAction.new(href: new_supply_purchase_path(@supply), icon: "fa-plus", label: t("supplies.card.buy_more"),
                                      turbo_stream: true)
    render Components::ItemMenu.new(label: t("supplies.card.more"), actions: menu_actions)
  end

  # Someone a therapy is shared with may restock its supplies, not change them.
  def menu_actions
    return [] unless @supply.profile_id == @viewer.id

    [
      Components::Action.new(href: edit_supply_path(@supply), icon: "fa-pen", label: t("supplies.card.edit"), turbo_stream: true),
      Components::Action.new(href: supply_path(@supply), icon: "fa-trash", label: t("supplies.card.destroy"),
                             method: :delete, confirm: destroy_confirm, danger: true)
    ]
  end

  def destroy_confirm
    count = @supply.purchase_count
    if count.positive?
      t("supplies.form.confirm_destroy_with_purchases", name: @supply.name, count: count)
    else
      t("supplies.form.confirm_destroy", name: @supply.name)
    end
  end
end
