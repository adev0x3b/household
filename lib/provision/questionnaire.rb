# frozen_string_literal: true

module Provision
  # A destination's settings asked one by one, each by its kind
  # (Provision::Settings), or kept as they are — the defaults shown, one
  # answer for all — with the provider's key asked whenever it is missing.
  class Questionnaire
    SIZE = /\A\d+\s*(B|KB|MB|GB|TB)?\z/i

    def initialize(prompt)
      @prompt = prompt
    end

    # name → value for every setting, from the defaults given (the file's
    # values, else the catalogue's) or the answers. kept: the keys GitHub
    # holds already, never asked for.
    def settings(list, defaults, kept: [])
      show(list, defaults)
      answers = if @prompt.yes?("Keep these?", default: true)
        list.to_h { [ _1.name, defaults.fetch(_1.name, _1.default) ] }
      else
        list.each_with_object({}) { |setting, pairs| pairs[setting.name] = ask(setting, defaults.fetch(setting.name, setting.default)) if wanted?(setting, pairs) }
      end
      key = key_for(answers["ASSISTANT_PROVIDER"])
      answers[key] = @prompt.secret(Settings.find(key).question, default: answers[key]) if key && answers[key].to_s.empty? && !kept.include?(key) && list.any? { _1.name == key }
      answers
    end

    def ask(setting, default)
      case setting.kind
      when :switch then @prompt.yes?(setting.question, default: default.to_s != "off") ? "on" : "off"
      when :count then until_valid(setting, default) { _1.empty? || _1.match?(/\A\d+\z/) }
      when :size then until_valid(setting, default) { _1.match?(SIZE) }
      when :memory then until_valid(setting, default) { _1.empty? || _1.match?(SIZE) }
      when :choice then @prompt.choose(setting.question, setting.choices, default: default)
      when :secret then @prompt.secret(setting.question, default: default)
      else @prompt.ask(setting.question, default: default)
      end.to_s.strip
    end

    private

    def show(list, defaults)
      list.each do |setting|
        value = defaults.fetch(setting.name, setting.default).to_s
        shown = if setting.secret? then value.empty? ? "none" : "set, ends in #{value[-4..]}"
        else value.empty? ? "(none)" : value
        end
        @prompt.say("  #{setting.name} = #{shown}")
      end
    end

    # The other provider's key, and Ollama's address under another provider, aren't asked.
    def wanted?(setting, pairs)
      provider = pairs["ASSISTANT_PROVIDER"]
      case setting.name
      when "ANTHROPIC_API_KEY", "OPENAI_API_KEY" then provider.nil? || key_for(provider) == setting.name
      when "OLLAMA_BASE_URL" then provider.nil? || provider == "ollama"
      else true
      end
    end

    def key_for(provider) = { "anthropic" => "ANTHROPIC_API_KEY", "openai" => "OPENAI_API_KEY" }[provider]

    def until_valid(setting, default)
      5.times do
        answer = @prompt.ask(setting.question, default: default).to_s.strip
        return answer if yield(answer)

        @prompt.say("Not a value for #{setting.name}: #{answer.inspect}")
      end
      raise Stop, "no value for #{setting.name}"
    end
  end
end
