# frozen_string_literal: true

require "test_helper"

# A copy without the pipeline (compose.yml, docs/self-hosting.md): the
# release's image, three services and a tunnel on request, the app's volumes,
# every setting read from household.env, the limits left to the admin, and a
# file Docker Compose accepts.
class Provision::ComposeTest < ActiveSupport::TestCase
  COMPOSE = Rails.root.join("compose.yml")

  test "the database, the web server published on its two ports, the jobs after it, the tunnel when asked; three volumes" do
    compose = YAML.safe_load(COMPOSE.read, aliases: true)
    assert_equal %w[db web job cloudflared], compose.fetch("services").keys
    assert_equal %w[db storage secrets], compose.fetch("volumes").keys
    assert_nil compose.dig("services", "db", "ports"), "the database is the containers' alone"
    assert_equal [ "${BIND:-127.0.0.1}:${PORT:-8080}:80", "${BIND:-127.0.0.1}:${TLS_PORT:-8443}:443" ], compose.dig("services", "web", "ports")
    assert_equal [ "cloudflare" ], compose.dig("services", "cloudflared", "profiles")
    assert_match(/\Acloudflare\/cloudflared:\d{4}\.\d+\.\d+\z/, compose.dig("services", "cloudflared", "image"), "a version, never latest")
    assert_equal "service_healthy", compose.dig("services", "web", "depends_on", "db", "condition")
    assert_equal "service_healthy", compose.dig("services", "job", "depends_on", "web", "condition")
    assert_equal "bin/jobs", compose.dig("services", "job", "command")
    assert_includes compose.dig("services", "web", "healthcheck", "test").join(" "), "http://localhost${MOUNT_PATH:-}/up"
    %w[web job].each do |service|
      assert_equal [ "storage:/rails/storage", "secrets:/rails/secrets" ], compose.dig("services", service, "volumes")
      assert_equal "unless-stopped", compose.dig("services", service, "restart")
    end
  end

  test "the app's image is the release's: named where each release pins it, told to the app, never built here" do
    compose = YAML.safe_load(COMPOSE.read, aliases: true)
    %w[web job].each do |service|
      assert_equal "${HOUSEHOLD_IMAGE}", compose.dig("services", service, "image"), service
      assert_equal "${HOUSEHOLD_IMAGE}", compose.dig("services", service, "environment", "HOUSEHOLD_IMAGE"), service
      assert_nil compose.dig("services", service, "build"), service
    end
    assert_not compose.dig("services", "web", "environment").key?("KAMAL_DESTINATION"), "a copy of one's own is none of the pipeline's destinations"
  end

  test "every limit is read from the env file with nothing for a default, so the admin sets it unless the file does" do
    environment = YAML.safe_load(COMPOSE.read, aliases: true).dig("services", "web", "environment")
    Platform::LIMITS.each_value { assert_equal "${#{_1.env}:-}", environment.fetch(_1.env), _1.env }
  end

  test "every other setting of a copy without the pipeline is read from the env file, with production's default" do
    environment = YAML.safe_load(COMPOSE.read, aliases: true).dig("services", "web", "environment")
    limits = Platform::LIMITS.values.map(&:env)
    Provision::Settings.compose.reject { limits.include?(_1.name) }.each do |setting|
      assert_equal "${#{setting.name}:-#{setting.default_for("production")}}", environment.fetch(setting.name), setting.name
    end
    (Provision::Settings.names - Provision::Settings.compose.map(&:name)).each { assert_not environment.key?(_1), "#{_1} is the pipeline's" }
    assert_match(/\A\$\{APP_HOST:\?/, environment.fetch("APP_HOST"), "the address is required")
    assert_match(/\A\$\{POSTGRES_PASSWORD:\?/, environment.fetch("HOUSEHOLD_DATABASE_PASSWORD"), "the password is required")
    assert_equal "${FORCE_SSL:-on}", environment.fetch("FORCE_SSL")
  end

  test "docker compose accepts it" do
    skip "docker compose isn't here" unless system("docker compose version > /dev/null 2>&1")
    Tempfile.create("destination.env") do |env|
      env.write("HOUSEHOLD_IMAGE=ghcr.io/owner/household:2026.11.1\nAPP_HOST=household.test\nPOSTGRES_PASSWORD=not-a-real-password\n")
      env.flush
      assert system("docker", "compose", "-f", COMPOSE.to_s, "--env-file", env.path, "config", "--quiet"), "docker compose config refused compose.yml"
    end
  end
end
