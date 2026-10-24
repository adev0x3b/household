# frozen_string_literal: true

# What the assistant's Test press and its model list answer with, on the
# settings page and in the first setup alike: whether the form's values
# reach the model, and which models the provider lists. Both ask the
# provider with values that may not be saved yet.
module Assistant::ConnectionAnswers
  extend ActiveSupport::Concern

  private

  # draft: an Assistant::Setting holding the form's values, not saved. A key
  # left blank means the one in use, as it does on save. The model list is
  # drawn again from the same values, so a key just typed lists its models.
  def answer_connection_test(draft)
    provider = draft.provider.to_s
    credentials = { ollama_url: draft.ollama_url, api_key: draft.api_key(provider).presence || ::Assistant.api_key(provider) }
    render turbo_stream: [
      turbo_stream.replace(Views::Assistant::Settings::ConnectionStatus::FRAME_ID,
                           connection_status(provider: provider, model: draft.model.to_s, tested: true, **credentials)),
      turbo_stream.replace(Views::Assistant::Settings::ModelOptions::FRAME_ID, model_options(provider, **credentials))
    ]
  end

  # The models of the provider the form picked, asked with what is in use:
  # a key typed but not saved reaches the list through the Test press.
  def answer_model_list(provider)
    provider = ::Assistant.provider.to_s unless ::Assistant::Setting::PROVIDERS.include?(provider)
    render model_options(provider), layout: false
  end

  def connection_status(provider:, model:, tested: false, **credentials)
    ::Assistant::Connection.check!(provider: provider, model: model, **credentials)
    Views::Assistant::Settings::ConnectionStatus.new(ok: true, provider: provider, model: model, tested: tested)
  rescue ::Assistant::Connection::Error => e
    Views::Assistant::Settings::ConnectionStatus.new(ok: false, provider: provider, model: model, tested: tested, reason: e.message)
  end

  def model_options(provider, **credentials)
    Views::Assistant::Settings::ModelOptions.new(provider: provider, models: ::Assistant::Connection.models(provider, **credentials))
  end
end
