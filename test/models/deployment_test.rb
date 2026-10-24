# frozen_string_literal: true

require "test_helper"

# Deployment: the facts about the running process, from what the image was
# built with and what Kamal, or a release's compose.yml, started it with.
class DeploymentTest < ActiveSupport::TestCase
  SHA = "0123456789abcdef0123456789abcdef01234567"
  IMAGE = "ghcr.io/adev0x3b/household:2026.11.2@sha256:#{"ab" * 32}"

  isolate_env "APP_VERSION", "KAMAL_VERSION", "KAMAL_DESTINATION", "HOUSEHOLD_IMAGE"

  test "an image built without a version has none" do
    assert_not Deployment.versioned?
    assert_nil Deployment.version
    assert_nil Deployment.short_version
    assert_nil Deployment.commit_url
  end

  test "the version is the commit the image was built from, flagged when the checkout was dirty" do
    ENV["APP_VERSION"] = SHA

    assert_predicate Deployment, :versioned?
    assert_equal "0123456", Deployment.short_version
    assert_equal "https://github.com/example/household/commit/#{SHA}", Deployment.commit_url
    assert_not Deployment.uncommitted?

    ENV["APP_VERSION"] = "#{SHA}_uncommitted_9f9f9f"
    assert_predicate Deployment, :uncommitted?
    assert_equal SHA, Deployment.sha
  end

  test "without a version in the image, the tag Kamal runs stands in when it is a commit" do
    ENV["KAMAL_VERSION"] = SHA
    assert_equal SHA, Deployment.version

    ENV["KAMAL_VERSION"] = "latest-production"
    assert_nil Deployment.version

    ENV["APP_VERSION"] = "fedcba9876543210fedcba9876543210fedcba98"
    ENV["KAMAL_VERSION"] = SHA
    assert_equal "fedcba9", Deployment.short_version
  end

  test "the destination is Kamal's, production, staging or dev; anything else is none" do
    assert_nil Deployment.destination
    assert_not Deployment.deployed?

    ENV["KAMAL_DESTINATION"] = "staging"
    assert_equal "staging", Deployment.destination
    assert_predicate Deployment, :deployed?

    ENV["KAMAL_DESTINATION"] = "production"
    assert_equal "production", Deployment.destination

    ENV["KAMAL_DESTINATION"] = "dev"
    assert_equal "dev", Deployment.destination

    ENV["KAMAL_DESTINATION"] = "qa"
    assert_nil Deployment.destination
  end

  test "a copy handed a release's image and no destination is self-hosted, and knows its release" do
    assert_predicate Deployment, :pipeline?
    assert_nil Deployment.release

    ENV["HOUSEHOLD_IMAGE"] = IMAGE
    assert_predicate Deployment, :self_hosted?
    assert_not Deployment.pipeline?
    assert_equal Deployment::Release.new(repository: "adev0x3b/household", version: "2026.11.2"), Deployment.release
    assert_equal "https://github.com/adev0x3b/household/releases/tag/v2026.11.2", Deployment.release.notes_url

    ENV["KAMAL_DESTINATION"] = "production"
    assert_predicate Deployment, :pipeline?
    assert_nil Deployment.release
  end

  test "an image that isn't a pinned release leaves a self-hosted copy without one" do
    digest = "@sha256:#{"ab" * 32}"
    [ "household:local", "ghcr.io/adev0x3b/household:2026.11.2", "ghcr.io/adev0x3b/household:2026.13.1#{digest}",
      "ghcr.io/adev0x3b/household:#{SHA}#{digest}", "ghcr.io/adev0x3b/other:2026.11.2#{digest}" ].each do |image|
      ENV["HOUSEHOLD_IMAGE"] = image
      assert_predicate Deployment, :self_hosted?, image
      assert_nil Deployment.release, image
    end
  end

  test "releases compare by their calendar versions as numbers" do
    release = ->(version) { Deployment::Release.new(repository: "adev0x3b/household", version: version) }

    assert release["2026.11.10"].newer_than?(release["2026.11.9"])
    assert release["2027.1.1"].newer_than?(release["2026.12.4"])
    assert_not release["2026.11.2"].newer_than?(release["2026.11.2"])
    assert_not release["2026.10.3"].newer_than?(release["2026.11.1"])
  end

  test "booted at boot, the database answers, and the worker isn't checked here" do
    assert_operator Deployment.booted_at, :<=, Time.current
    assert_predicate Deployment, :database_ok?
    assert_nil Deployment.worker_alive?
  end
end
