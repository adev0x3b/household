# frozen_string_literal: true

# A batch of a supply: the collection it was bought for, how much (and,
# once saved, how much is left), its dates, how long it keeps once opened, and what it
# cost if the buyer says.
class Views::SupplyPurchases::Modals::Form < Views::Base
  # The form for a purchase the assistant drafted, posting under its supply.
  def self.draft(purchase, viewer:, housemates:, **)
    new(supply_purchase: purchase, url: Rails.application.routes.url_helpers.supply_purchases_path(purchase.supply), current_profile: viewer,
        available_transaction_counterparties: housemates)
  end

  def initialize(supply_purchase:, url:, current_profile:, available_transaction_counterparties:)
    @supply_purchase = supply_purchase
    @url = url
    @current_profile = current_profile
    @available_transaction_counterparties = available_transaction_counterparties
  end

  def view_template
    render Components::Modal.new(size: :medium, section: :healthcare) do |modal|
      modal.modal_header(
        title: modal_title,
        subtitle: @supply_purchase.supply&.name,
        icon: "fa-box-open"
      )

      render Components::Form.new(record: @supply_purchase, url: @url, submit_text: submit_text, modal: modal) do |f|
        render_collection_field
        render_quantity_purchased_field(f)
        render_quantity_remaining_field(f) if @supply_purchase.persisted?
        render_purchased_on_field(f)
        render_expires_on_field(f)
        render_opened_on_field(f)
        render_pao_days_override_field(f)
        render_cost_section
      end
    end
  end

  private

  def modal_title
    @supply_purchase.persisted? ? t("supply_purchases.form.edit_title") : t("supply_purchases.form.new_title")
  end

  def submit_text
    @supply_purchase.persisted? ? t("supply_purchases.form.update") : t("supply_purchases.form.create")
  end

  # The therapy (a Healthcare collection) the batch was bought for.
  def render_collection_field
    render Components::Field.new(label: t("supply_purchases.form.collection_label"), control_id: "supply_purchase_collection_id",
                                 select: true) do
      select(name: "supply_purchase[collection_id]", id: "supply_purchase_collection_id") do
        option(value: "", selected: @supply_purchase.collection_id.blank?) { t("collections.sections.healthcare.picker.none") }

        collections.each do |collection|
          option(value: collection.id, selected: @supply_purchase.collection_id == collection.id) { collection.name }
        end
      end
    end
  end

  def render_quantity_purchased_field(f)
    form_field(f, :quantity_purchased, label: t("supply_purchases.form.quantity_purchased_label")) do |field|
      f.number_field :quantity_purchased, value: number_value(@supply_purchase.quantity_purchased), step: "any", min: "0", class: "input is-medium", required: true, aria: field.aria
    end
  end

  def render_quantity_remaining_field(f)
    form_field(f, :quantity_remaining, label: t("supply_purchases.form.quantity_remaining_label")) do |field|
      f.number_field :quantity_remaining, value: number_value(@supply_purchase.quantity_remaining), step: "any", min: "0", class: "input is-medium", required: true, aria: field.aria
    end
  end

  def render_purchased_on_field(f)
    form_field(f, :purchased_on, label: t("supply_purchases.form.purchased_on_label")) do |field|
      f.date_field :purchased_on, class: "input is-medium", required: true, aria: field.aria
    end
  end

  def render_expires_on_field(f)
    form_field(f, :expires_on, label: t("supply_purchases.form.expires_on_label")) do |field|
      f.date_field :expires_on, class: "input is-medium", aria: field.aria
    end
  end

  def render_opened_on_field(f)
    form_field(f, :opened_on, label: t("supply_purchases.form.opened_on_label")) do |field|
      f.date_field :opened_on, class: "input is-medium", aria: field.aria
    end
  end

  def render_pao_days_override_field(f)
    form_field(f, :pao_days_override, label: t("supply_purchases.form.pao_days_override_label"),
                                      help: t("supply_purchases.form.pao_days_override_help")) do |field|
      f.number_field :pao_days_override, class: "input is-medium", aria: field.aria
    end
  end

  def collections
    Collection.choices_for(@current_profile, section: :healthcare)
  end

  def render_cost_section
    fieldset(class: "supply-purchase-form__cost-section") do
      legend(class: "label") { t("supply_purchases.form.cost_section.label") }
      p(class: "help") { t("supply_purchases.form.cost_section.help") }

      render Views::Transactions::CostFields.new(cost: @supply_purchase.cost&.details, currency: @current_profile.household.currency,
                                                 counterparties: @available_transaction_counterparties)
    end
  end
end
