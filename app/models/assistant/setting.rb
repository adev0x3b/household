# frozen_string_literal: true

# The assistant's configuration as an admin set it on /assistant/settings:
# the provider, how to reach it (Ollama's URL, the API keys: encrypted,
# never shown back), the model and its tuning. One row.
#
# Until the row exists the environment decides (.env, see Assistant); once
# an admin saves, the row owns the whole configuration (a blank field is the
# provider's own default), except the API keys: a key never saved still
# comes from the environment.
class Assistant::Setting < ApplicationRecord
  PROVIDERS = %w[ollama anthropic openai].freeze
  # The providers that need an API key, and so have a column for it.
  KEYED_PROVIDERS = %w[anthropic openai].freeze
  THINKING = %w[none low medium high].freeze
  MODEL_FORMAT = %r{\A[\w.:/-]+\z}
  URL_FORMAT = %r{\Ahttps?://[^\s/]+\S*\z}

  encrypts :anthropic_api_key, :openai_api_key

  belongs_to :updated_by, class_name: "Profile", optional: true

  normalizes :provider, :model, :thinking_effort, :anthropic_api_key, :openai_api_key, with: ->(value) { value.to_s.strip.presence }
  normalizes :ollama_url, with: ->(value) { value.to_s.strip.delete_suffix("/v1").chomp("/").presence }

  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, presence: true, format: { with: MODEL_FORMAT, allow_blank: true }
  validates :ollama_url, format: { with: URL_FORMAT }, allow_nil: true
  validates :ollama_url, presence: true, if: -> { provider == "ollama" }
  validates :thinking_effort, inclusion: { in: THINKING }, allow_nil: true
  validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }, allow_nil: true
  validates :context_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 1_024 }, allow_nil: true
  validates :max_output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 256 }, allow_nil: true
  validate :key_for_provider

  # The current configuration changed: the next read builds it again.
  after_commit { Current.assistant_setting = Current.llm_context = nil }

  # The saved row, or nil while the environment still decides.
  def self.saved
    found = (Current.assistant_setting ||= first || :none)
    found == :none ? nil : found
  end

  # What the form starts from: the saved row, else the environment's values.
  def self.for_form
    saved || new(provider: Assistant.provider.to_s, model: Assistant.model, ollama_url: Assistant.ollama_url,
                 context_tokens: Assistant.context_tokens, temperature: Assistant.temperature,
                 thinking_effort: Assistant.thinking_effort, max_output_tokens: Assistant.max_output_tokens)
  end

  def self.key_column(provider) = (:"#{provider}_api_key" if KEYED_PROVIDERS.include?(provider.to_s))

  def api_key(provider)
    column = self.class.key_column(provider)
    column && self[column]
  end

  # The saved key's last four characters, all a page ever shows of it.
  def key_hint(provider) = api_key(provider)&.last(4)

  # The form's values. A key field is never filled back, so a blank one
  # keeps the saved key; only a typed key replaces it.
  def assign_settings(values)
    values = values.to_h.stringify_keys
    KEYED_PROVIDERS.each { |provider| values.delete(self.class.key_column(provider).to_s) if values[self.class.key_column(provider).to_s].blank? }
    assign_attributes(values)
    self
  end

  private

  # A keyed provider needs its key: typed here or in the environment.
  def key_for_provider
    return unless KEYED_PROVIDERS.include?(provider)
    return if api_key(provider).present? || ENV["#{provider.upcase}_API_KEY"].present?

    errors.add(self.class.key_column(provider), :blank)
  end
end
