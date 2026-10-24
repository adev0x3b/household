# frozen_string_literal: true

# What the assistant cost each household this month: messages, tokens, and
# the money where the provider has prices. The admin reads it to see who
# uses the assistant and how much, so the heaviest household comes first.
class Views::Assistant::Settings::UsageCard < Views::Base
  def initialize(rows:)
    @rows = rows
  end

  def view_template
    render Components::Panel.new(title: t("assistant.settings.sections.usage"), hint: t("assistant.settings.usage.hint")) do
      if @rows.empty?
        p(class: "report-hint") { t("assistant.settings.usage.none") }
      else
        table(class: "table is-fullwidth is-narrow assistant-settings__usage") do
          thead do
            tr do
              th { t("assistant.settings.usage.household") }
              th { t("assistant.settings.usage.messages") }
              th { t("assistant.settings.usage.input_tokens") }
              th { t("assistant.settings.usage.output_tokens") }
              th { t("assistant.settings.usage.cost") } if costs?
            end
          end
          tbody { @rows.each { |row| usage_row(row) } }
        end
      end
    end
  end

  private

  def costs? = @rows.any?(&:cost?)

  def usage_row(row)
    tr do
      td { row.household.name }
      td { format_figure(row.messages, :count) }
      td { format_figure(row.input_tokens, :count) }
      td { format_figure(row.output_tokens, :count) }
      td { row.cost? ? money(row.cost) : t("assistant.settings.usage.free") } if costs?
    end
  end

  # RubyLLM's registry prices every provider in US dollars.
  def money(value) = "#{ActiveSupport::NumberHelper.number_to_rounded(value, precision: 4, strip_insignificant_zeros: true, locale: I18n.locale)} USD"
end
