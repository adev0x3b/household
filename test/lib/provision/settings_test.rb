# frozen_string_literal: true

require "test_helper"

# The one list of what a destination may be asked and what every reader of
# the environment defaults (Provision::Settings): the four destinations'
# defaults, and what is asked where.
class Provision::SettingsTest < ActiveSupport::TestCase
  test "every name is unique and upper case, with a string default for every destination" do
    names = Provision::Settings.names
    assert_equal names.uniq, names
    names.each { assert_match(/\A[A-Z][A-Z0-9_]+\z/, _1) }
    Provision::Settings::DESTINATIONS.each do |destination|
      Provision::Settings.defaults(destination).each { |name, value| assert_kind_of String, value, "#{name} on #{destination}" }
    end
    assert_equal "on", Provision::Settings.find("UPLOADS").default
    assert_raises(KeyError) { Provision::Settings.find("NOT_A_SETTING") }
  end

  test "production, staging and dev are on and unlimited; the demo turns off what a public playground mustn't do" do
    %w[production staging dev].each do |destination|
      defaults = Provision::Settings.defaults(destination)
      %w[ASSISTANT UPLOADS PICTURES INVITATIONS PUSH_NOTIFICATIONS].each { assert_equal "on", defaults.fetch(_1), "#{_1} on #{destination}" }
      assert_equal "", defaults.fetch("ASSISTANT_MESSAGES_PER_DAY")
      assert_equal "", defaults.fetch("BOOK_LOOKUPS_PER_DAY")
    end
    demo = Provision::Settings.defaults("demo")
    assert_equal "on", demo.fetch("ASSISTANT")
    %w[UPLOADS PICTURES INVITATIONS PUSH_NOTIFICATIONS].each { assert_equal "off", demo.fetch(_1), _1 }
    assert_equal "30", demo.fetch("ASSISTANT_MESSAGES_PER_DAY")
    assert_equal "50", demo.fetch("BOOK_LOOKUPS_PER_DAY")
    assert_equal "64MB", demo.fetch("FILES_QUOTA")
    assert_equal "50GB", Provision::Settings.defaults("production").fetch("FILES_QUOTA")
    assert_equal "512MB", Provision::Settings.defaults("staging").fetch("FILES_QUOTA")
    assert_equal "512MB", Provision::Settings.defaults("dev").fetch("FILES_QUOTA")
  end

  test "the demo's three accounts are open on the demo and on dev, nowhere else, and the tests' copy of the demo's settings is the catalogue's" do
    assert_equal Provision::Settings::DEMO_ACCOUNTS, Provision::Settings.defaults("demo").fetch("OPEN_ACCOUNTS")
    assert_equal Provision::Settings::DEMO_ACCOUNTS, Provision::Settings.defaults("dev").fetch("OPEN_ACCOUNTS")
    assert_equal "", Provision::Settings.defaults("production").fetch("OPEN_ACCOUNTS")
    assert_equal "", Provision::Settings.defaults("staging").fetch("OPEN_ACCOUNTS")

    expected = DemoBuilders::DEMO_SETTINGS.keys.to_h { [ _1, Provision::Settings.defaults("demo").fetch(_1) ] }
    assert_equal expected, DemoBuilders::DEMO_SETTINGS
  end

  test "what is asked where: open accounts and their password on dev and the demo, the deploy token on production and staging" do
    asked = ->(destination) { Provision::Settings.for(destination).map(&:name) }
    assert_includes asked.call("demo"), "OPEN_ACCOUNTS"
    assert_includes asked.call("dev"), "DEMO_PASSWORD"
    assert_not_includes asked.call("production"), "OPEN_ACCOUNTS"
    assert_not_includes asked.call("staging"), "DEMO_PASSWORD"
    assert_includes asked.call("production"), "DEPLOY_DISPATCH_TOKEN"
    assert_not_includes asked.call("demo"), "DEPLOY_DISPATCH_TOKEN"
    assert_equal Provision::Settings.names - %w[OPEN_ACCOUNTS DEMO_PASSWORD], asked.call("staging")
  end

  test "a copy without the pipeline is passed everything but the deploy token, which only the pipeline's console uses" do
    assert_equal Provision::Settings.names - %w[DEPLOY_DISPATCH_TOKEN WEB_MEMORY JOB_MEMORY DB_MEMORY], Provision::Settings.compose.map(&:name)
  end

  test "the keys are the secrets, everything else a plain setting" do
    assert_equal %w[ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_BOOKS_API_KEY DEMO_PASSWORD DEPLOY_DISPATCH_TOKEN], Provision::Settings.secret.map(&:name)
    assert_equal Provision::Settings.names - Provision::Settings.secret.map(&:name) - Provision::Settings.caps.map(&:name), Provision::Settings.clear.map(&:name)
    assert_equal %w[ollama anthropic openai], Provision::Settings.find("ASSISTANT_PROVIDER").choices
  end

  test "the memory caps size the containers and never reach the app: capped where destinations share a machine with production, production not" do
    assert_equal %w[WEB_MEMORY JOB_MEMORY DB_MEMORY], Provision::Settings.caps.map(&:name)
    Provision::Settings.caps.each { assert_predicate _1, :pipeline_only? }
    %w[staging dev demo].each do |destination|
      assert_equal %w[1GB 1GB], Provision::Settings.defaults(destination).values_at("WEB_MEMORY", "JOB_MEMORY"), destination
    end
    assert_equal [ "", "", "" ], Provision::Settings.defaults("production").values_at("WEB_MEMORY", "JOB_MEMORY", "DB_MEMORY")
  end
end
