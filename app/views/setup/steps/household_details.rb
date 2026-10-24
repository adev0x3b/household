# frozen_string_literal: true

# The first setup's household step (Setup::HouseholdDetails): its name and
# the currency its money is counted in.
class Views::Setup::Steps::HouseholdDetails < Views::Base
  CURRENCY_LIST_ID = "setup-currencies"

  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("setup.steps.household.title"), hint: t("setup.steps.household.hint")) do
      form_field(@form, :name, label: t("setup.steps.household.name"), required: true) do |field|
        @form.text_field :name, required: true, autocomplete: "organization", placeholder: t("setup.steps.household.name_placeholder"),
                                class: "input", aria: field.aria
      end
      currency_field
    end
  end

  private

  # Any three-letter code is taken; the list only saves typing the usual ones.
  def currency_field
    form_field(@form, :currency, label: t("setup.steps.household.currency"), help: t("setup.steps.household.currency_help"), required: true) do |field|
      @form.text_field :currency, required: true, maxlength: 3, pattern: "[A-Za-z]{3}", autocapitalize: "characters", autocomplete: "off",
                                  spellcheck: "false", list: CURRENCY_LIST_ID, class: "input", aria: field.aria
      datalist(id: CURRENCY_LIST_ID) { ::Setup::HouseholdDetails::CURRENCIES.each { |code| option(value: code) } }
    end
  end
end
