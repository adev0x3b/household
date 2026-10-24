# frozen_string_literal: true

# Asks a provider whether a model is there and which models it has, without
# a completion, so the check is quick and costs nothing. Credentials default
# to the current configuration; the settings form passes the ones it is about
# to save.
#
#   Assistant::Connection.check!(provider: "ollama", model: "qwen3-8b-household")  # raises Error, saying why
#   Assistant::Connection.models("anthropic")  # => ["claude-haiku-4-5-20251001", …], [] when it can't be asked
module Assistant
  class Connection < ApplicationClient
    class Error < ApplicationClient::Error; end

    TIMEOUT = 5 # seconds
    LIST_TIMEOUT = 3
    ANTHROPIC_API = "https://api.anthropic.com/v1"
    OPENAI_API = "https://api.openai.com/v1"

    # ollama_url and api_key are what the form holds, nil for the configured ones.
    def self.check!(provider:, model:, ollama_url: nil, api_key: nil)
      case provider.to_s
      when "ollama" then ollama!(model.to_s, ollama_url || Assistant.ollama_url)
      when "anthropic" then described!("Anthropic", model.to_s, api_key || Assistant.api_key(:anthropic))
      when "openai" then described!("OpenAI", model.to_s, api_key || Assistant.api_key(:openai))
      else raise Error, "unknown provider #{provider.inspect}"
      end
      true
    end

    # The provider's models, sorted; [] when it can't be asked.
    def self.models(provider, ollama_url: nil, api_key: nil)
      case provider.to_s
      when "ollama" then ollama_names(ollama_url || Assistant.ollama_url, timeout: LIST_TIMEOUT)
      when "anthropic" then listed("Anthropic", api_key || Assistant.api_key(:anthropic))
      when "openai" then listed("OpenAI", api_key || Assistant.api_key(:openai))
      else []
      end
    rescue Error
      []
    end

    def self.ollama!(model, base)
      raise Error, "no Ollama server is set" if base.blank?

      names = ollama_names(base, timeout: TIMEOUT)
      return if names.include?(model) || names.include?("#{model}:latest")

      raise Error, "the Ollama server doesn't have #{model} (it has: #{names.join(", ")})"
    end

    # Whether Anthropic's or OpenAI's Models API knows `model`, asked with this key.
    def self.described!(name, model, key)
      raise Error, "no #{name} API key is set" if key.blank?

      response = perform(get("#{api(name)}/models/#{URI.encode_uri_component(model)}", headers(name, key)), service: name)
      return if response.code.to_s.start_with?("2")

      raise Error, case response.code.to_s
      when "404" then "#{name} has no model #{model}"
      when "401", "403" then "#{name} refused the API key (#{response.code})"
      else "#{name} answered #{response.code}"
      end
    end

    def self.ollama_names(base, timeout:)
      service = "the Ollama server at #{base}"
      tags = URI.join(base.to_s.delete_suffix("/v1").chomp("/") + "/", "api/tags")
      json(perform(get(tags), timeout: timeout, service: service), service: service).fetch("models", []).map { _1["name"] }.sort
    rescue URI::InvalidURIError
      raise Error, "#{base.inspect} isn't an address"
    end

    # A Models API list ({ data: [{ id: … }] }), sorted; [] without a key.
    def self.listed(name, key)
      return [] if key.blank?

      query = name == "Anthropic" ? "?limit=100" : ""
      json(perform(get("#{api(name)}/models#{query}", headers(name, key)), timeout: LIST_TIMEOUT, service: name), service: name)
        .fetch("data", []).filter_map { _1["id"] }.sort
    end

    def self.api(name) = name == "Anthropic" ? ANTHROPIC_API : OPENAI_API

    def self.headers(name, key)
      name == "Anthropic" ? { "x-api-key" => key.to_s, "anthropic-version" => "2023-06-01" } : { "Authorization" => "Bearer #{key}" }
    end
    private_class_method :ollama!, :described!, :ollama_names, :listed, :api, :headers
  end
end
