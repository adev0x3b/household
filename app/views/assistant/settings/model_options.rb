# frozen_string_literal: true

# The model field's suggestions, from what the chosen provider says it has.
# When it can't be asked (offline, or no key yet) the name is typed by hand.
class Views::Assistant::Settings::ModelOptions < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "assistant-settings-models"
  LIST_ID = "assistant-settings-model-list"

  def initialize(provider: nil, models: nil, src: nil)
    @provider = provider
    @models = models
    @src = src
  end

  def view_template
    turbo_frame_tag(FRAME_ID, src: @src, loading: (:lazy if @src), data: { assistant_settings_target: "models" }) do
      if @models.nil?
        p(class: "help") { t("assistant.settings.fields.models_loading") }
      else
        datalist(id: LIST_ID) { @models.each { |model| option(value: model) } }
        p(class: "help") { @models.any? ? t("assistant.settings.fields.models_found", count: @models.size) : t("assistant.settings.fields.models_none") }
      end
    end
  end
end
