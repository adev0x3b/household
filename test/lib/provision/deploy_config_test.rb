# frozen_string_literal: true

require "test_helper"

# Every destination's settings come from the environment through
# config/deploy.yml and config/deploy.<destination>.yml, rendered here as
# Kamal renders them (ERB, YAML, one deep merge): each catalogue setting
# once, with the destination's default where the environment has nothing —
# unset, or "" as the Deploy workflow passes an unset variable — and the
# environment's value where it has one; a key only where the environment
# has it.
class Provision::DeployConfigTest < ActiveSupport::TestCase
  INSTALLATION = {
    "DEPLOY_HOST" => "box.example", "KAMAL_REGISTRY_USERNAME" => "owner", "GITHUB_REPOSITORY" => "owner/household",
    "PRODUCTION_HOST" => "example.com", "STAGING_HOST" => "staging.example.com", "DEV_HOST" => "dev.example.com",
    "DEMO_HOST" => "demo.example.com"
  }.freeze
  # Where each memory cap lands among Kamal's options for docker run.
  CAPPED = { "WEB_MEMORY" => %w[servers web options], "JOB_MEMORY" => %w[servers job options], "DB_MEMORY" => %w[accessories db options] }.freeze

  Provision::Settings::DESTINATIONS.each do |destination|
    test "#{destination} takes the catalogue's defaults when the environment has nothing, unset or empty" do
      [ nil, "" ].each do |nothing|
        with_env(INSTALLATION.merge(Provision::Settings.names.to_h { [ _1, nothing ] })) do
          env = kamal_env(destination)
          Provision::Settings.clear.each do |setting|
            assert_equal setting.default_for(destination), env.fetch(setting.name), "#{setting.name} on #{destination} (#{nothing.inspect})"
          end
          Provision::Settings.secret.each { |setting| assert_not env.key?(setting.name), "#{setting.name} is listed with nothing to pass" }
        end
      end
    end
  end

  test "the environment's values win, and a key is passed only where there is one" do
    values = Provision::Settings.clear.to_h { [ _1.name, "set-#{_1.name.downcase}" ] }
    with_env(INSTALLATION.merge(values, "ANTHROPIC_API_KEY" => "sk-ant-x", "DEMO_PASSWORD" => "something-long")) do
      env = kamal_env("demo")
      values.each { |name, value| assert_equal value, env.fetch(name) }
      assert_equal %w[ANTHROPIC_API_KEY DEMO_PASSWORD], Provision::Settings.secret.map(&:name) & env.keys
      assert_equal :secret, env.fetch("ANTHROPIC_API_KEY")
    end
  end

  test "what Kamal needs of the environment is still asked, and the destination's own values stay its own" do
    with_env(INSTALLATION) do
      assert_equal "household-demo-db", kamal_env("demo").fetch("DB_HOST")
      assert_equal "demo.example.com", kamal_env("demo").fetch("APP_HOST")
      assert_equal "example.com", kamal_env("production").fetch("APP_HOST")
      assert_equal "1", kamal_env("dev").fetch("DEPLOY_GITHUB_CANNED")
    end
  end

  test "the path to live under: empty at the root, the one given otherwise, and the proxy's health check follows it" do
    with_env(INSTALLATION.merge("MOUNT_PATH" => nil)) { assert_equal "", kamal_env("production").fetch("MOUNT_PATH") }
    with_env(INSTALLATION.merge("MOUNT_PATH" => "")) { assert_equal "", kamal_env("production").fetch("MOUNT_PATH") }
    with_env(INSTALLATION.merge("MOUNT_PATH" => "/love")) do
      assert_equal "/love", kamal_env("production").fetch("MOUNT_PATH")
      assert_equal "/love/up", render("deploy.yml").dig("proxy", "healthcheck", "path")
    end
    with_env(INSTALLATION.merge("MOUNT_PATH" => nil)) { assert_equal "/up", render("deploy.yml").dig("proxy", "healthcheck", "path") }
  end

  test "each container's memory: the destination's default cap, the environment's where it has one, none where neither says" do
    with_env(INSTALLATION.merge(Provision::Settings.caps.to_h { [ _1.name, "" ] })) do
      Provision::Settings::DESTINATIONS.each do |destination|
        Provision::Settings.caps.each do |setting|
          assert_equal setting.default_for(destination), memory(destination, setting.name).to_s, "#{setting.name} on #{destination}"
        end
      end
    end
    with_env(INSTALLATION.merge("WEB_MEMORY" => "768MB", "JOB_MEMORY" => "512MB", "DB_MEMORY" => "512MB")) do
      assert_equal(%w[768MB 512MB 512MB], %w[WEB_MEMORY JOB_MEMORY DB_MEMORY].map { memory("demo", _1) })
      assert_equal "768MB", memory("production", "WEB_MEMORY")
    end
  end

  test "the job container, which alone sends mail, takes the relay's name to its address where one is given, the certificate still checked against the name" do
    with_env(INSTALLATION.merge("SMTP_HOST" => "mail.example.com", "SMTP_HOST_ADDRESS" => "")) do
      assert_equal [ "host.docker.internal:host-gateway" ], merged("production").dig("servers", "job", "options", "add-host")
    end
    with_env(INSTALLATION.merge("SMTP_HOST" => "mail.example.com", "SMTP_HOST_ADDRESS" => "100.64.0.7")) do
      assert_equal [ "host.docker.internal:host-gateway", "mail.example.com:100.64.0.7" ], merged("staging").dig("servers", "job", "options", "add-host")
      assert_equal "host.docker.internal:host-gateway", merged("staging").dig("servers", "web", "options", "add-host")
      assert_equal "mail.example.com", kamal_env("staging").fetch("SMTP_HOST")
    end
    with_env(INSTALLATION.merge("SMTP_HOST" => "", "SMTP_HOST_ADDRESS" => "100.64.0.7")) do
      assert_raises(RuntimeError, match: /SMTP_HOST/) { render("deploy.yml") }
    end
  end

  private

  def memory(destination, setting) = merged(destination).dig(*CAPPED.fetch(setting)).to_h["memory"]

  # The merged env as Kamal reads it: `clear`, plus the names of `secret`
  # (each worth :secret here; the values come from .kamal/secrets-common).
  def kamal_env(destination)
    env = merged(destination).fetch("env")
    env.fetch("clear").merge(env.fetch("secret").to_h { [ _1.split(":").first, :secret ] })
  end

  def merged(destination) = [ "deploy.yml", "deploy.#{destination}.yml" ].map { render(_1) }.inject { |base, own| base.deep_merge(own) }

  def render(file)
    YAML.safe_load(ERB.new(Rails.root.join("config", file).read, trim_mode: "-").result, aliases: true)
  end
end
