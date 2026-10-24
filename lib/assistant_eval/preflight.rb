# frozen_string_literal: true

# Is the model there before we spend a run on it? A run against an offline
# model server, or one that doesn't have the model, scores nothing but
# errors. Asks the provider without a completion (Assistant::Connection),
# with the credentials configured now (/assistant/settings, else .env); its
# error says which it was.
#
#   Preflight.check!(provider: "ollama", model: "qwen3-8b-household")  # raises Unavailable
module AssistantEval
  module Preflight
    Unavailable = Assistant::Connection::Error

    module_function

    def check!(provider:, model:)
      Assistant::Connection.check!(provider: provider, model: model)
    end
  end
end
