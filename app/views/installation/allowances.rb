# frozen_string_literal: true

# What this copy lets its people do (Installation::Allowances): a switch
# each, the assistant's daily budget, the Files quota and how many people a
# household holds and each member invites.
class Views::Installation::Allowances < Views::Base
  # form: the builder for this section's fields (fields_for), section: the Installation::Allowances.
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("installation.allowances.title"), hint: t("installation.allowances.hint")) do
      fieldset(class: "report-choices") do
        legend(class: "is-sr-only") { t("installation.allowances.title") }
        ::Installation::Allowances::SWITCHES.each { |name| switch(name) }
      end
      div(class: "report-fields") do
        count_field(:assistant_messages_per_day, min: 0)
        quota_field
      end
      div(class: "report-fields") do
        count_field(:household_size, min: 1)
        count_field(:invitations_per_member, min: 1)
      end
    end
  end

  private

  def switch(name)
    label(class: "report-choice") do
      @form.check_box name, aria: { describedby: @form.field_id(name, :help) }
      span(class: "report-choice__text") do
        strong { t("installation.allowances.switches.#{name}.name") }
        span(class: "help", id: @form.field_id(name, :help)) { t("installation.allowances.switches.#{name}.help") }
      end
    end
  end

  # A whole number, empty for no limit.
  def count_field(name, min:)
    form_field(@form, name, label: t("installation.allowances.#{name}"), help: t("installation.allowances.#{name}_help")) do |field|
      @form.number_field name, min:, step: 1, inputmode: "numeric", placeholder: t("installation.no_limit"), class: "input", aria: field.aria
    end
  end

  # A whole number of megabytes or gigabytes, so a quota under a gigabyte
  # (staging's 512 MB) is kept as it is.
  def quota_field
    form_field(@form, :files_quota_amount, label: t("installation.allowances.files_quota"), help: t("installation.allowances.files_quota_help"),
                                           control: false) do |field|
      div(class: "field has-addons") do
        div(class: "control is-expanded") do
          @form.number_field :files_quota_amount, min: 1, step: 1, inputmode: "numeric", required: true, class: "input", aria: field.aria
        end
        div(class: "control") do
          div(class: "select") do
            @form.select :files_quota_unit, ::Installation::Allowances::QUOTA_UNITS.map { [ t("installation.allowances.quota_units.#{_1}"), _1 ] }, {},
                         aria: { label: t("installation.allowances.files_quota_unit") }
          end
        end
      end
    end
  end
end
