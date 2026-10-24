# frozen_string_literal: true

# Money on a day: what for, how much and which way, its category, who it
# was paid to or by (a name, or a housemate — then they read it too, as an
# income), how it was paid, how it repeats and — once saved — whether it
# is paid. What it is about (a lab report's day: "Add a cost") travels in
# hidden fields.
class Views::Transactions::Modals::Form < Views::Occurrences::Form
  private

  def form_data
    { controller: "transaction-form", action: "input->transaction-form#refresh change->transaction-form#refresh" }
  end

  def fields(f)
    render_text_field(f, :title, "transactions.form.title_label", placeholder_key: "transactions.form.title_placeholder", autofocus: true)
    details_fields(f) do |d|
      render_about_fields(d)
      render_amount_field(d)
      render_details_select(d, :kind, "transactions.form.kind_label", select_options(Transaction::Details.kinds.keys) { |key| t("transactions.kind.#{key}") },
                            data: { transaction_form_target: "kind" })
      render_details_select(d, :category, "transactions.form.category_label", select_options(Transaction::Details.categories.keys) { |key| t("transactions.category.#{key}") })
      render_counterparty_field(d)
      render_details_select(d, :payment_method, "transactions.form.payment_method_label", select_options(Transaction::Details.payment_methods.keys) { |key| t("transactions.payment_method.#{key}") })
    end
    render_text_area(f, :notes, "transactions.form.description_label", placeholder_key: "transactions.form.description_placeholder")
    render_event_fields
    render_collection_picker
    render_status_field(f)
  end

  # Money coming in is received rather than paid. The done option carries
  # both words, so the form can change it with the kind before anything is
  # saved (transaction_form_controller.js).
  def status_options
    super.map do |label, status|
      next [ label, status ] unless status == "completed"

      word = event.received_by?(@current_profile, details) ? "received" : "completed"
      [ t("transactions.status.#{word}"), status,
        { data: { transaction_form_target: "doneOption", paid_label: t("transactions.status.completed"), received_label: t("transactions.status.received") } } ]
    end
  end

  # What a new payment is about, as the link that opened the form said.
  def render_about_fields(d)
    return if details.persisted? || details.about.nil?

    d.hidden_field :about_type
    d.hidden_field :about_id
  end

  def render_amount_field(d)
    form_field(d, :amount, label: t("transactions.form.amount_label"), record: details, validation_attribute: :amount_cents) do |field|
      d.number_field :amount,
                     class: "input is-medium",
                     placeholder: t("transactions.form.amount_placeholder"),
                     step: currency.step,
                     min: currency.step,
                     value: details.amount&.to_s,
                     data: { transaction_form_target: "amount" },
                     required: required_attribute?(details, :amount, validation_attribute: :amount_cents), aria: field.aria
    end
  end

  # A saved payment keeps the currency it was made in; a new one will be in
  # the household's (Occurrences::FormSave::Transaction).
  def currency = Currency.new(details.currency || @current_profile.household.currency)

  def profile_counterparty_mode?
    details.counterparty_mode == "profile"
  end

  def render_counterparty_field(d)
    form_field(d, :counterparty_mode, label: t("transactions.form.counterparty_label"), required: false, select: true) do |field|
      d.select :counterparty_mode, counterparty_mode_options, {},
               data: { action: "change->transaction-form#syncCounterpartyMode", transaction_form_target: "counterpartyMode" }, aria: field.aria
    end

    form_field(d, :counterparty, label: t("transactions.form.counterparty_text_label"), required: false,
                                 data: { transaction_form_target: "counterpartyTextSection" }, hidden: profile_counterparty_mode?) do |field|
      d.text_field :counterparty,
                   class: "input is-medium",
                   placeholder: t("transactions.form.counterparty_placeholder"),
                   disabled: profile_counterparty_mode?,
                   data: { transaction_form_target: "counterpartyTextInput" }, aria: field.aria
    end

    form_field(d, :counterparty_profile_id, label: t("transactions.form.counterparty_profile_label"), required: false, select: true,
                                            data: { transaction_form_target: "counterpartyProfileSection" }, hidden: !profile_counterparty_mode?) do |field|
      d.select :counterparty_profile_id, profile_options, { include_blank: t("transactions.form.counterparty_profile_placeholder") },
               **counterparty_profile_state, aria: field.aria
    end
  end

  # The housemate is the series' (both read the whole series): on a day of
  # a recurring one it is sent only when the whole series is chosen.
  def counterparty_profile_state
    data = { transaction_form_target: "counterpartyProfileSelect" }
    return { disabled: !profile_counterparty_mode?, data: data } unless apply_to?

    { disabled: true, data: data.merge(apply_to_scope: "series", apply_to_held: ("1" if profile_counterparty_mode?)) }
  end

  def counterparty_mode_options
    [
      [ t("transactions.form.counterparty_mode_text"), "text" ],
      [ t("transactions.form.counterparty_mode_profile"), "profile" ]
    ]
  end

  def profile_options
    names = Profiles::DisplayNames.new(@housemates)
    @housemates.map { |profile| [ names.of(profile), profile.id ] }
  end
end
