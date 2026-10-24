# frozen_string_literal: true

require "test_helper"

# /admin/deployment: the admin sees what this copy runs, and with a
# token the pipeline's frames and the navbar's freeze switch; without one
# the page says where the token is set. What fills the frames is tested
# with Admin::DeliveriesController, the presses with
# Admin::DeliveryRequestsController.
class Admin::DeploymentsControllerTest < ActionDispatch::IntegrationTest
  include CannedPipeline

  isolate_env "APP_VERSION", "DEPLOY_DISPATCH_TOKEN", "KAMAL_DESTINATION", "HOUSEHOLD_IMAGE"

  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
    sign_in @admin
  end

  test "the admin sees the version the image was built from and what answers" do
    ENV["APP_VERSION"] = SHA

    get admin_deployment_path

    assert_response :success
    assert_select ".report-status--good"
    assert_select ".deployment__facts a[href='https://github.com/example/household/commit/#{SHA}']", text: "0123456"
    assert_select ".deployment__facts", text: /#{Regexp.escape(RUBY_VERSION)}/
    assert_select ".deployment__facts .status-badge--good", text: /Answering/
    assert_select ".deployment__facts .status-badge--neutral", text: /Not checked here/
    assert_select ".deployment__facts", text: /Environment\s*test/
    assert_select ".report-flag", count: 0
  end

  test "on one of Kamal's destinations, the page names it; a dirty checkout is flagged; no version is neutral" do
    ENV["KAMAL_DESTINATION"] = "staging"
    get admin_deployment_path
    assert_select ".deployment__facts", text: /Environment\s*Staging/

    ENV["APP_VERSION"] = "#{SHA}_uncommitted_abc123"
    get admin_deployment_path
    assert_select ".report-flag", text: /uncommitted/

    ENV.delete("APP_VERSION")
    get admin_deployment_path
    assert_select ".report-status--neutral", text: /Version unknown/
  end

  test "without a token: a notice, no frames and no freeze switch" do
    get admin_deployment_path

    assert_select ".notice--neutral a[href=?]", admin_settings_path
    assert_select "turbo-frame##{Views::Admin::Deployments::ThisCopy::FRAME_ID} .deployment__facts"
    assert_select "turbo-frame##{Views::Admin::Deliveries::Console::FRAME_ID}", count: 0
    assert_select "turbo-frame##{Views::Admin::Deliveries::Metrics::FRAME_ID}", count: 0
    assert_select ".page-controls a[href*=freeze]", count: 0
  end

  test "with a token: the pipeline's frames load lazily and morph, and the navbar holds the freeze switch" do
    with_deploy_token

    canned { get admin_deployment_path }

    assert_select "turbo-frame##{Views::Admin::Deliveries::Console::FRAME_ID}[loading=lazy][refresh=morph][src=?]", console_admin_delivery_path
    assert_select "turbo-frame##{Views::Admin::Deliveries::Metrics::FRAME_ID}[loading=lazy][refresh=morph][src=?]", metrics_admin_delivery_path
    assert_select ".page-controls a[href=?][data-turbo-stream]:not(.is-active)", new_admin_delivery_request_path(kind: :freeze)
    assert_select ".notice", count: 0

    canned(frozen: true) { get admin_deployment_path }
    assert_select ".page-controls a[href=?].page-controls__action.is-active", new_admin_delivery_request_path(kind: :unfreeze)
  end

  test "with GitHub not answering, the page still says what this copy runs, with no freeze switch, and the failure is reported" do
    with_deploy_token

    assert_error_reported(Delivery::Github::Error) do
      swapping(Delivery::Github, :perform, ->(_request) { raise Delivery::Github::Error, "GitHub isn't answering (OpenTimeout)" }) { get admin_deployment_path }
    end

    assert_response :success
    assert_select "title", text: /Deployment/
    assert_select "turbo-frame##{Views::Admin::Deployments::ThisCopy::FRAME_ID} .deployment__facts"
    assert_select ".page-controls a[href*=freeze]", count: 0
  end

  test "a self-hosted copy shows itself alone: its release, the update command, and nothing of the pipeline" do
    ENV["APP_VERSION"] = SHA
    ENV["HOUSEHOLD_IMAGE"] = "ghcr.io/adev0x3b/household:2026.11.2@sha256:#{"ab" * 32}"
    with_deploy_token

    get admin_deployment_path

    assert_response :success
    assert_select ".report-status--good", text: /Version 2026\.11\.2/
    assert_select ".deployment__facts a[href='https://github.com/adev0x3b/household/releases/tag/v2026.11.2']", text: "2026.11.2"
    assert_select ".deployment__facts", text: /Environment\s*Self-hosted/
    assert_select ".report-hint code", text: Deployment::UPDATE_COMMAND
    assert_select ".notice", count: 0
    assert_select ".deployment turbo-frame", count: 0
    assert_select ".page-controls", count: 0
  end

  test "a self-hosted copy says whether a newer release is out, as the daily check last found it" do
    ENV["HOUSEHOLD_IMAGE"] = "ghcr.io/adev0x3b/household:2026.11.2@sha256:#{"ab" * 32}"
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    get admin_deployment_path
    assert_select ".report-status--neutral", text: /Not checked yet/

    Deployment::Update.remember(Deployment::Release.new(repository: "adev0x3b/household", version: "2026.11.2"))
    get admin_deployment_path
    assert_select ".report-status--good", text: /Up to date.*2026\.11\.2 is the newest release/m

    Deployment::Update.remember(Deployment::Release.new(repository: "adev0x3b/household", version: "2026.11.3"))
    get admin_deployment_path
    assert_select ".report-status--warning.report-status--action", text: /2026\.11\.3 is out/
    assert_select ".report-status--action a[href='https://github.com/adev0x3b/household/releases/tag/v2026.11.3']"

    with_env("RELEASE_CHECK" => "off") { get admin_deployment_path }
    assert_select ".report-status--neutral", text: /doesn't look for new releases/
    assert_select ".report-status a[href=?]", admin_settings_path
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end

  test "a self-hosted copy on an image that isn't a release names its commit" do
    ENV["APP_VERSION"] = SHA
    ENV["HOUSEHOLD_IMAGE"] = "household:local"

    get admin_deployment_path

    assert_select ".deployment__facts a[href$='/commit/#{SHA}']", text: "0123456"
    assert_select ".deployment__facts", text: /Environment\s*Self-hosted/
    assert_select ".report-tag", text: "Updates", count: 0
  end

  test "a database that doesn't answer makes the card critical; a worker not heard from, a warning" do
    swapping(Deployment, :database_ok?, -> { false }) { get admin_deployment_path }
    assert_select ".report-status--critical"
    assert_select ".deployment__facts .status-badge--critical", text: /Not answering/

    swapping(Deployment, :worker_alive?, -> { false }) { get admin_deployment_path }
    assert_select ".report-status--warning"
    assert_select ".deployment__facts .status-badge--critical", text: /#{Lexicon::Worker::FRESH.in_minutes.to_i}/
  end

  test "members have none of this, nor a link to it" do
    sign_in profiles(:bob)

    get admin_deployment_path
    assert_redirected_to root_path

    get root_path
    assert_select "a[href=?]", admin_deployment_path, count: 0
  end
end
