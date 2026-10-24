# frozen_string_literal: true

module Installation
  # Which model the assistant talks to, as a step of the first setup: the
  # provider, how to reach it and the model, checked as the
  # Assistant::Setting they become. Its tuning keeps the provider's defaults
  # until the admin changes it on /assistant/settings. Asked only when the
  # installation allows the assistant.
  #
  #   assistant = Installation::Assistant.for_setup.assign(params)
  #   assistant.valid?
  #   assistant.setting.save!
  class Assistant
    include ActiveModel::Model

    FIELDS = %i[provider model ollama_url anthropic_api_key openai_api_key].freeze

    # The Assistant::Setting this step makes, which the step's fields draw
    # and whose errors it reports.
    attr_reader :setting

    # The fields read as the setting's, so a form builder draws them.
    delegate(*FIELDS, to: :setting)

    validate :as_a_setting

    def self.param_key = :assistant

    def self.fields = FIELDS

    # The environment's choice, as /assistant/settings starts from.
    def self.for_setup = new(::Assistant::Setting.for_form)

    def initialize(setting)
      @setting = setting
    end

    def assign(values)
      setting.assign_settings(values.to_h.symbolize_keys.slice(*FIELDS))
      self
    end

    # Asked only when the installation allows the assistant.
    def asked?(form) = form.step(Installation::Allowances).assistant

    private

    def as_a_setting
      setting.errors.each { |error| errors.import(error) } unless setting.valid?
    end
  end
end
