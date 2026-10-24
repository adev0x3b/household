# frozen_string_literal: true

# Buying an ingredient: how much, in what unit, when, and what it cost if
# the buyer says (a payment saved with the purchase).
class Views::IngredientPurchases::Modals::Form < Views::Base
  # The form for a purchase the assistant drafted, posting under its ingredient.
  def self.draft(purchase, housemates:, **)
    new(ingredient_purchase: purchase, url: Rails.application.routes.url_helpers.ingredient_purchases_path(purchase.ingredient),
        available_transaction_counterparties: housemates)
  end

  def initialize(ingredient_purchase:, url:, available_transaction_counterparties:)
    @purchase = ingredient_purchase
    @url = url
    @available_transaction_counterparties = available_transaction_counterparties
  end

  def view_template
    render Components::Modal.new(size: :medium, section: :pantry) do |modal|
      modal.modal_header(title: modal_title, subtitle: @purchase.ingredient&.name, icon: "fa-cart-plus")

      render Components::Form.new(record: @purchase, url: @url, submit_text: submit_text, modal: modal) do |f|
        render_quantity_field(f)
        render_unit_field unless @purchase.persisted?
        render_purchased_on_field(f)
        render_cost_section
      end
    end
  end

  private

  def modal_title
    @purchase.persisted? ? t("ingredient_purchases.form.edit_title") : t("ingredient_purchases.form.new_title")
  end

  def submit_text
    @purchase.persisted? ? t("ingredient_purchases.form.update") : t("ingredient_purchases.form.create")
  end

  def render_quantity_field(f)
    form_field(f, :quantity, label: t("ingredient_purchases.form.quantity_label")) do |field|
      f.number_field :quantity, value: number_value(@purchase.quantity), step: "any", min: "0", class: "input is-medium", required: true, aria: field.aria
    end
  end

  # Blank means the ingredient's own unit. Resolved server-side through
  # IngredientPurchase#unit_name=, like the ingredient form's unit field.
  def render_unit_field
    render Components::Field.new(label: t("ingredient_purchases.form.unit_label"), control_id: "ingredient_purchase_unit_name",
                                 errors: Forms::Errors.new(@purchase).for(:unit)) do |field|
      input(
        type: "text",
        id: "ingredient_purchase_unit_name",
        name: "ingredient_purchase[unit_name]",
        value: @purchase.unit&.name,
        list: Components::UnitsDatalist::ID,
        class: "input is-medium",
        placeholder: @purchase.ingredient&.unit&.name || t("ingredient_purchases.form.unit_placeholder"),
        aria: field.aria
      )
      render Components::UnitsDatalist.new(profile: @purchase.profile)
    end
  end

  def render_purchased_on_field(f)
    form_field(f, :purchased_on, label: t("ingredient_purchases.form.purchased_on_label")) do |field|
      f.date_field :purchased_on, class: "input is-medium", required: true, aria: field.aria
    end
  end

  def render_cost_section
    fieldset(class: "ingredient-purchase-form__cost-section") do
      legend(class: "label") { t("ingredient_purchases.form.cost_section.label") }
      p(class: "help") { t("ingredient_purchases.form.cost_section.help") }

      render Views::Transactions::CostFields.new(cost: @purchase.cost&.details, currency: @purchase.profile.household.currency,
                                                 counterparties: @available_transaction_counterparties)
    end
  end
end
