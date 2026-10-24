# frozen_string_literal: true

require "test_helper"

# Deployment::UpdateCheckJob asks for a newer release once a day, only on a
# self-hosted copy running a release whose admin allows it.
class Deployment::UpdateCheckJobTest < ActiveJob::TestCase
  IMAGE = "ghcr.io/adev0x3b/household:2026.11.2@sha256:#{"ab" * 32}"

  isolate_env "KAMAL_DESTINATION"

  def checks
    asked = []
    swapping(Deployment::CheckForUpdate, :call, ->(release) { asked << release.version }) { Deployment::UpdateCheckJob.perform_now }
    asked
  end

  test "a self-hosted copy running a release asks about it" do
    with_env("HOUSEHOLD_IMAGE" => IMAGE) { assert_equal [ "2026.11.2" ], checks }
  end

  test "the pipeline's copies, an image that isn't a release, and an admin who turned it off ask nothing" do
    assert_empty checks
    with_env("HOUSEHOLD_IMAGE" => "household:local") { assert_empty checks }
    with_env("HOUSEHOLD_IMAGE" => IMAGE, "KAMAL_DESTINATION" => "production") { assert_empty checks }
    with_env("HOUSEHOLD_IMAGE" => IMAGE, "RELEASE_CHECK" => "off") { assert_empty checks }
  end

  test "GitHub not answering is reported as a warning" do
    with_env("HOUSEHOLD_IMAGE" => IMAGE) do
      swapping(Deployment::Releases, :latest, ->(_repository) { raise Deployment::Releases::Error, "GitHub's releases isn't answering (OpenTimeout)" }) do
        assert_error_reported(Deployment::Releases::Error) { Deployment::UpdateCheckJob.perform_now }
      end
    end
  end
end
