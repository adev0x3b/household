# frozen_string_literal: true

# A healthcare supply: its name, category, unit, the stock that counts as
# low and how many days it keeps once opened. A new one can come with its
# first batch and what it cost.
class Views::Supplies::Modals::Form < Views::Base
  def initialize(supply:, url:, available_transaction_counterparties: Profile.none)
    @supply = supply
    @url = url
    @available_transaction_counterparties = available_transaction_counterparties
  end

  def view_template
    render Components::Modal.new(size: :medium, section: :healthcare) do |modal|
      modal.modal_header(
        title: modal_title,
        icon: "fa-box-open"
      )

      render Components::Form.new(record: @supply, url: @url, submit_text: submit_text, modal: modal) do |f|
        render_name_field(f)
        render_category_field(f)
        render_unit_label_field(f)
        render_low_stock_threshold_field(f)
        render_pao_days_field(f)
        render_initial_purchase_section unless @supply.persisted?
      end
    end
  end

  private

  def modal_title
    @supply.persisted? ? t("supplies.form.edit_title") : t("supplies.form.new_title")
  end

  def submit_text
    @supply.persisted? ? t("supplies.form.update") : t("supplies.form.create")
  end

  def render_name_field(f)
    form_field(f, :name, label: t("supplies.form.name_label")) do |field|
      f.text_field :name,
                   class: "input is-medium",
                   placeholder: t("supplies.form.name_placeholder"),
                   autofocus: true,
                   required: required_attribute?(@supply, :name), aria: field.aria
    end
  end

  def render_category_field(f)
    form_field(f, :category, label: t("supplies.form.category_label"), select: true) do |field|
      f.select :category, category_options, {}, required: required_attribute?(@supply, :category), aria: field.aria
    end
  end

  def render_unit_label_field(f)
    form_field(f, :unit_label, label: t("supplies.form.unit_label_label")) do |field|
      f.text_field :unit_label,
                   class: "input is-medium",
                   placeholder: t("supplies.form.unit_label_placeholder"),
                   required: required_attribute?(@supply, :unit_label), aria: field.aria
    end
  end

  def render_low_stock_threshold_field(f)
    form_field(f, :low_stock_threshold, label: t("supplies.form.low_stock_threshold_label")) do |field|
      f.number_field :low_stock_threshold, value: number_value(@supply.low_stock_threshold), step: "any", min: 0, class: "input is-medium", aria: field.aria
    end
  end

  def render_pao_days_field(f)
    form_field(f, :pao_days, label: t("supplies.form.pao_days_label"), help: t("supplies.form.pao_days_help")) do |field|
      f.number_field :pao_days, min: 0, class: "input is-medium", aria: field.aria
    end
  end

  def category_options
    select_options(Supply.categories.keys) { |key| t("supplies.category.#{key}") }
  end

  # A new supply can come with its first batch: one purchase, with no rows
  # to add or remove.

  def render_initial_purchase_section
    purchase = @supply.supply_purchases.first || @supply.supply_purchases.build

    fieldset(class: "supply-form__initial-purchase") do
      legend(class: "label") { t("supplies.form.initial_purchase.label") }
      p(class: "help") { t("supplies.form.initial_purchase.help") }

      render_purchase_quantity_field(purchase)
      render_purchase_purchased_on_field(purchase)
      render_purchase_expires_on_field(purchase)
      render_purchase_opened_on_field(purchase)
      render_purchase_pao_override_field(purchase)
      render_cost_section
    end
  end

  def render_cost_section
    fieldset(class: "supply-purchase-form__cost-section") do
      legend(class: "label") { t("supply_purchases.form.cost_section.label") }
      p(class: "help") { t("supply_purchases.form.cost_section.help") }

      render Views::Transactions::CostFields.new(cost: nil, currency: @supply.profile.household.currency,
                                                 counterparties: @available_transaction_counterparties)
    end
  end

  def nested_field_prefix
    "supply[supply_purchases_attributes][0]"
  end

  def nested_field_id(attribute) = "supply_supply_purchases_attributes_0_#{attribute}"

  def first_purchase_errors = @first_purchase_errors ||= Forms::Errors.new(@supply).rows(:supply_purchases)[0]

  def render_purchase_quantity_field(purchase)
    render Components::Field.new(label: t("supply_purchases.form.quantity_purchased_label"),
                                 control_id: nested_field_id(:quantity_purchased),
                                 errors: first_purchase_errors.for(:quantity_purchased)) do |field|
      input(
        type: "number", step: "any", min: "0",
        id: nested_field_id(:quantity_purchased),
        name: "#{nested_field_prefix}[quantity_purchased]",
        value: number_value(purchase.quantity_purchased),
        class: "input is-medium",
        aria: field.aria
      )
    end
  end

  def render_purchase_purchased_on_field(purchase)
    render Components::Field.new(label: t("supply_purchases.form.purchased_on_label"), control_id: nested_field_id(:purchased_on),
                                 errors: first_purchase_errors.for(:purchased_on)) do |field|
      input(
        type: "date",
        id: nested_field_id(:purchased_on),
        name: "#{nested_field_prefix}[purchased_on]",
        value: (purchase.purchased_on || Date.current).iso8601,
        class: "input is-medium",
        aria: field.aria
      )
    end
  end

  def render_purchase_expires_on_field(purchase)
    render Components::Field.new(label: t("supply_purchases.form.expires_on_label"), control_id: nested_field_id(:expires_on),
                                 errors: first_purchase_errors.for(:expires_on)) do |field|
      input(
        type: "date",
        id: nested_field_id(:expires_on),
        name: "#{nested_field_prefix}[expires_on]",
        value: purchase.expires_on&.iso8601,
        class: "input is-medium",
        aria: field.aria
      )
    end
  end

  def render_purchase_opened_on_field(purchase)
    render Components::Field.new(label: t("supply_purchases.form.opened_on_label"), control_id: nested_field_id(:opened_on),
                                 errors: first_purchase_errors.for(:opened_on)) do |field|
      input(
        type: "date",
        id: nested_field_id(:opened_on),
        name: "#{nested_field_prefix}[opened_on]",
        value: purchase.opened_on&.iso8601,
        class: "input is-medium",
        aria: field.aria
      )
    end
  end

  def render_purchase_pao_override_field(purchase)
    render Components::Field.new(label: t("supply_purchases.form.pao_days_override_label"),
                                 control_id: nested_field_id(:pao_days_override),
                                 help: t("supply_purchases.form.pao_days_override_help"),
                                 errors: first_purchase_errors.for(:pao_days_override)) do |field|
      input(
        type: "number", min: "0",
        id: nested_field_id(:pao_days_override),
        name: "#{nested_field_prefix}[pao_days_override]",
        value: purchase.pao_days_override&.to_s,
        class: "input is-medium",
        aria: field.aria
      )
    end
  end
end
