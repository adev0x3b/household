# frozen_string_literal: true

# What something cost, inside the form of the thing it paid for: a visit's
# fee, a meal out's bill, a purchase. Amount and payment method, and who
# was paid when the form asks (a name, or a housemate among `counterparties`),
# posted under `transaction[...]` beside the form's own record for
# Occurrences::FormSave or Purchases::Save to make the one expense from;
# the rest of the expense is inferred. Logging a cost is optional, so
# nothing is required until an amount is typed; then the method is
# (transaction_form_controller.js, and the expense's own validation).
#
#   render Views::Transactions::CostFields.new(cost: purchase.cost&.details, currency: household.currency, counterparties: housemates)
class Views::Transactions::CostFields < Views::Base
  # cost: the cost's money as its day reads it (Transaction::Details), or
  # nil for one not logged yet; currency: the household's, which a cost not
  # logged yet will be in; counterparties: the housemates who may have been
  # paid, for a form that asks who was. A form that doesn't (a fee, a bill:
  # Occurrences::FormSave reads only the amount and the method) leaves them
  # out.
  def initialize(cost:, currency:, counterparties: nil)
    @cost = cost || Transaction::Details.new
    @currency = Currency.new(@cost.currency || currency)
    @counterparties = counterparties
  end

  def view_template
    div(class: "cost-fields", data: { controller: "transaction-form", action: "input->transaction-form#refresh change->transaction-form#refresh" }) do
      render_amount_field
      render_counterparty_fields if @counterparties
      render_payment_method_field
    end
  end

  private

  def field_id(attribute) = "transaction_#{attribute}"

  def render_amount_field
    render Components::Field.new(label: t("transactions.form.amount_label"), control_id: field_id(:amount)) do
      input(type: "number", step: @currency.step, min: @currency.step, id: field_id(:amount), name: "transaction[amount]", value: @cost.amount&.to_s,
            class: "input is-medium", placeholder: t("transactions.form.amount_placeholder"), data: { transaction_form_target: "amount" })
    end
  end

  def profile_counterparty_mode? = @cost.counterparty_mode == "profile"

  # Typed, or picked among the housemates: only the field in use is shown
  # and sent (transaction_form_controller.js).
  def render_counterparty_fields
    render Components::Field.new(label: t("transactions.form.counterparty_label"), control_id: field_id(:counterparty_mode), select: true) do
      select(id: field_id(:counterparty_mode), name: "transaction[counterparty_mode]",
             data: { action: "change->transaction-form#syncCounterpartyMode", transaction_form_target: "counterpartyMode" }) do
        counterparty_mode_options.each do |label_text, value|
          option(value: value, selected: @cost.counterparty_mode == value) { label_text }
        end
      end
    end

    render Components::Field.new(label: t("transactions.form.counterparty_text_label"), control_id: field_id(:counterparty),
                                 data: { transaction_form_target: "counterpartyTextSection" }, hidden: profile_counterparty_mode?) do
      input(type: "text", id: field_id(:counterparty), name: "transaction[counterparty]", value: @cost.counterparty,
            class: "input is-medium", placeholder: t("transactions.form.counterparty_placeholder"), disabled: profile_counterparty_mode?,
            data: { transaction_form_target: "counterpartyTextInput" })
    end

    render Components::Field.new(label: t("transactions.form.counterparty_profile_label"), control_id: field_id(:counterparty_profile_id),
                                 select: true, data: { transaction_form_target: "counterpartyProfileSection" }, hidden: !profile_counterparty_mode?) do
      select(id: field_id(:counterparty_profile_id), name: "transaction[counterparty_profile_id]", disabled: !profile_counterparty_mode?,
             data: { transaction_form_target: "counterpartyProfileSelect" }) do
        option(value: "") { t("transactions.form.counterparty_profile_placeholder") }
        names = Profiles::DisplayNames.new(@counterparties)
        @counterparties.each do |profile|
          option(value: profile.id, selected: @cost.counterparty_profile_id == profile.id) { names.of(profile) }
        end
      end
    end
  end

  # A cost not logged yet has no method: the select says so rather than
  # showing the first one as if it had been chosen.
  def render_payment_method_field
    render Components::Field.new(label: t("transactions.form.payment_method_label"), control_id: field_id(:payment_method), select: true) do
      select(id: field_id(:payment_method), name: "transaction[payment_method]", data: { transaction_form_target: "paymentMethod" }) do
        option(value: "", selected: @cost.payment_method.blank?) { t("transactions.form.payment_method_blank") }
        Transaction::Details.payment_methods.each_key do |key|
          option(value: key, selected: @cost.payment_method == key) { t("transactions.payment_method.#{key}") }
        end
      end
    end
  end

  def counterparty_mode_options
    [
      [ t("transactions.form.counterparty_mode_text"), "text" ],
      [ t("transactions.form.counterparty_mode_profile"), "profile" ]
    ]
  end
end
