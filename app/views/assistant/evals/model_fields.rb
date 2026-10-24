# frozen_string_literal: true

# Provider + model for a run, defaulting to the assistant's settings; the
# model field suggests the configured model and whatever its provider has.
class Views::Assistant::Evals::ModelFields < Views::Base
  def initialize(models:, compact: false)
    @models = models
    @compact = compact
  end

  def view_template
    render Components::Field.new(label: t("assistant.evals.provider"), control_id: field_id("provider"), select: true,
                                 class: "eval-model-fields__provider") do
      select(id: field_id("provider"), name: "provider") do
        AssistantEval::Launcher::PROVIDERS.each do |provider|
          option(value: provider, selected: provider == ::Assistant.provider.to_s) { t("assistant.settings.providers.#{provider}.name") }
        end
      end
    end
    render Components::Field.new(label: t("assistant.evals.model"), control_id: field_id("model"), class: "eval-model-fields__model") do
      input(type: "text", id: field_id("model"), name: "model", value: ::Assistant.model, list: field_id("models"), class: "input",
            autocomplete: "off", spellcheck: "false")
    end
    datalist(id: field_id("models")) { @models.each { |model| option(value: model) } }
  end

  private

  # Unique per place: the run modal and the scenario form can share a page.
  def field_id(name) = "eval-#{@compact ? "try" : "run"}-#{name}"
end
