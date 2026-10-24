# frozen_string_literal: true

require "test_helper"

# A destination's settings asked by their kind, or kept as shown — the
# provider's key asked whenever it is missing.
class Provision::QuestionnaireTest < ActiveSupport::TestCase
  include ProvisionFakes

  LIST = Provision::Settings.for("demo")

  test "kept as they are: the defaults, with the provider's key asked when it is missing" do
    defaults = Provision::Settings.defaults("demo")
    answers = Provision::Questionnaire.new(prompt_with("y")).settings(LIST, defaults)
    assert_equal defaults.slice(*LIST.map(&:name)), answers

    anthropic = defaults.merge("ASSISTANT_PROVIDER" => "anthropic")
    answers = Provision::Questionnaire.new(prompt_with("y", "sk-ant-typed")).settings(LIST, anthropic)
    assert_equal "sk-ant-typed", answers["ANTHROPIC_API_KEY"]
    assert_equal "", answers["OPENAI_API_KEY"]
  end

  test "asked one by one: a switch as yes/no, a count checked, the other provider's key and Ollama's address skipped" do
    list = LIST.reject { %w[DEMO_PASSWORD GOOGLE_BOOKS_API_KEY].include?(_1.name) || !_1.app? }
    answers = Provision::Questionnaire.new(prompt_with(
                                             "n", # keep? no
                                             "n",                          # ASSISTANT off
                                             "", "", "", "",               # UPLOADS … PUSH_NOTIFICATIONS: the demo's defaults (off)
                                             "many", "12",                 # ASSISTANT_MESSAGES_PER_DAY: refused, then 12
                                             "",                           # BOOK_LOOKUPS_PER_DAY: 50
                                             "1 GB",                       # FILES_QUOTA
                                             "alex.demo",                  # OPEN_ACCOUNTS
                                             "2",                          # ASSISTANT_PROVIDER: anthropic
                                             "claude-sonnet-4-5",          # ASSISTANT_MODEL
                                             "sk-ant-x"                    # ANTHROPIC_API_KEY; OLLAMA_BASE_URL and OPENAI_API_KEY not asked
                                           )).settings(list, Provision::Settings.defaults("demo"))
    assert_equal "off", answers["ASSISTANT"]
    assert_equal "off", answers["UPLOADS"]
    assert_equal "12", answers["ASSISTANT_MESSAGES_PER_DAY"]
    assert_equal "50", answers["BOOK_LOOKUPS_PER_DAY"]
    assert_equal "1 GB", answers["FILES_QUOTA"]
    assert_equal "alex.demo", answers["OPEN_ACCOUNTS"]
    assert_equal "anthropic", answers["ASSISTANT_PROVIDER"]
    assert_equal "sk-ant-x", answers["ANTHROPIC_API_KEY"]
    assert_nil answers["OLLAMA_BASE_URL"]
    assert_nil answers["OPENAI_API_KEY"]
  end

  test "a memory cap: a size, or blank for the destination's default" do
    cap = Provision::Settings.find("WEB_MEMORY")
    assert_equal "768MB", Provision::Questionnaire.new(prompt_with("lots", "768MB")).ask(cap, "1GB")
    assert_equal "", Provision::Questionnaire.new(prompt_with("")).ask(cap, "")
  end
end
