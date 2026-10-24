# frozen_string_literal: true

require "test_helper"

# The pipeline's frames on /admin/deployment: with a token the console
# frame shows the pipeline (over the GitHub the fixtures draw) with its
# actions and polls while something runs, the metrics frame DORA's keys;
# on dev GitHub is stood in for; members have none of it.
class Admin::DeliveriesControllerTest < ActionDispatch::IntegrationTest
  include CannedPipeline

  isolate_env "APP_VERSION", "DEPLOY_DISPATCH_TOKEN", "KAMAL_DESTINATION", "DEPLOY_GITHUB_CANNED"

  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
    sign_in @admin
  end

  test "the console shows main, its CI and image, what production doesn't have yet, the held migration, and the actions" do
    with_deploy_token

    canned { get console_admin_delivery_path }

    assert_response :success
    assert_select ".deployment__commit--head a[href$='/commit/#{GithubFixtures::HEAD}']", text: "a1a1a1a"
    assert_select ".deployment__badges .status-badge--good", text: /CI passed/
    assert_select ".deployment__badges .status-badge--good", text: /Image built/
    assert_select ".deployment__commit--head .item-action[href=?][data-turbo-stream]", new_admin_delivery_request_path(kind: :ci)
    assert_select ".deployment__lane", 2
    assert_select ".deployment__lane-title", text: "A branch, on dev"
    assert_select ".deployment__lane:last-of-type .panel + .deployment__environments #deployment-staging + #deployment-demo + #deployment-production"
    assert_select ".notice--neutral", count: 0
    assert_select ".disclosure[open] .disclosure__result", text: /3 commits/
    assert_select ".disclosure .deployment__commit", 3
    assert_select ".deployment__held", text: /1 migration needs the app stopped/
    assert_select ".notice--action strong", text: /a1a1a1a needs the app stopped: 1 migration/
    assert_select ".notice--action", text: /migration took 12 seconds, 77 seconds behind the maintenance page/
    assert_select ".notice--action a[href=?][data-turbo-stream]", new_admin_delivery_request_path(kind: :release, version: GithubFixtures::HEAD)
  end

  test "each destination: version, who deployed it, against what feeds it, health, the last attempt, the rehearsal, and its actions" do
    with_deploy_token
    ENV["KAMAL_DESTINATION"] = "staging"

    canned { get console_admin_delivery_path }

    assert_select "#deployment-dev.report-status--warning" do
      assert_select ".deployment__facts a[href$='/tree/fix-the-bell']", text: "fix-the-bell"
      assert_select ".status-badge--warning", text: /The branch moved on by 1 commit/
      assert_select ".deployment__facts a[href$='/commit/#{GithubFixtures::DEV}']", text: "e7e7e7e"
      assert_select ".deployment__commit-title", text: "Ring the bell once per message"
      assert_select ".status-badge--neutral", text: /Fresh at the preview/
      assert_select ".deployment__facts", text: /by alex from the app #8: the bell rings twice/
      assert_select ".status-badge--neutral", text: /Not checked from here/
      assert_select ".deployment__facts a[href='https://github.com/example/household/pull/46']", text: "#46"
      assert_select ".deployment__commit-title", text: "Ring the bell once per message"
      assert_select ".status-badge--good", text: /Ready to merge/
      assert_select ".deployment__actions .item-action[href=?]", new_admin_delivery_request_path(kind: :preview)
      assert_select ".deployment__actions .item-action[href=?]", new_admin_delivery_request_path(kind: :merge)
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :restart, destination: "dev")
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :stop), text: /Stop/
      assert_select ".item-menu__entry[href='https://github.com/example/household/pull/46']", text: /Pull request #46/
      assert_select ".item-menu__entry[href=?]", "https://dev.household.example#{Rails.configuration.x.mount_path}"
      assert_select ".item-menu__entry", 4
      assert_select ".report-tag", count: 0
    end
    assert_select "#deployment-staging" do
      assert_select ".report-tag", text: "This copy"
      assert_select ".deployment__facts a[href$='/commit/#{GithubFixtures::HEAD}']", text: "a1a1a1a"
      assert_select ".status-badge--good", text: /Runs main's head/
      assert_select ".status-badge--good", text: /Answering/
      assert_select ".status-badge--good", text: /Rehearsal of a1a1a1a passed/
      assert_select ".deployment__actions .item-action[href=?]", new_admin_delivery_request_path(kind: :deploy, destination: "staging")
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :restart, destination: "staging")
      assert_select ".item-menu__entry[href=?]", "https://staging.household.example#{Rails.configuration.x.mount_path}"
      assert_select ".item-menu__entry[href*=rollback]", count: 0
    end
    assert_select "#deployment-demo" do
      assert_select ".deployment__facts a[href$='/commit/#{GithubFixtures::HEAD}']", text: "a1a1a1a"
      assert_select ".status-badge--good", text: /Runs main's head/
      assert_select ".deployment__actions .item-action[href=?]", new_admin_delivery_request_path(kind: :deploy, destination: "demo")
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :restart, destination: "demo")
      assert_select ".item-menu__entry[href*=rollback]", count: 0
      assert_select ".item-menu__entry[href*=release]", count: 0
    end
    assert_select "#deployment-production.report-status--warning" do
      assert_select ".deployment__facts a[href$='/commit/#{GithubFixtures::PRODUCTION}']", text: "b2b2b2b"
      assert_select ".deployment__facts", text: /by CI: Release a version/
      assert_select ".status-badge--warning", text: /3 commits behind main/
      assert_select ".status-badge--good", text: /Up/
      assert_select ".status-badge--warning", text: /deploy a1a1a1a/
      assert_select ".deployment__attempt", text: /held: needs the app stopped/
      assert_select ".deployment__actions .item-action[href=?]", new_admin_delivery_request_path(kind: :deploy, destination: "production", version: GithubFixtures::HEAD)
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :rollback)
      assert_select ".item-menu__entry.item-menu__entry--danger[href=?]", new_admin_delivery_request_path(kind: :release, version: GithubFixtures::HEAD)
      assert_select ".report-tag", count: 0
    end
  end

  test "the console polls while a run is live or something was just pressed, with the run's steps on top" do
    with_deploy_token

    canned { get console_admin_delivery_path }
    assert_select "[data-controller=frame-poll][data-frame-poll-active-value=true][data-frame-poll-interval-value='15000'][data-frame-poll-url-value=?]", console_admin_delivery_path
    assert_select "#deployment-run-201 .report-segments__segment", 13
    assert_select "#deployment-run-201 .report-status__now[role=status]", text: /staging \/ deploy staging · Kamal deploy staging/
    assert_select ".deployment__runs .deployment__run", 4

    done = [ workflow_run(status: "completed", conclusion: "success") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { done }) { canned { get console_admin_delivery_path } }
    assert_select "[data-controller=frame-poll][data-frame-poll-active-value=false]"
    assert_select "[id^=deployment-run-]", count: 0

    pressed = Delivery::Request.create!(profile: @admin, action: :deploy, destination: "staging", reason: "just now")
    swapping(Delivery::Github, :workflow_runs, ->(**) { done }) { canned { get console_admin_delivery_path } }
    assert_select "[data-controller=frame-poll][data-frame-poll-active-value=true]"
    assert_select "#deployment-request-#{pressed.id}" do
      assert_select ".status-badge--neutral", text: /Requested/
      assert_select ".deployment__run-title", text: /deploy main to Staging · just now/
      assert_select ".deployment__run-meta", text: /alice/
    end

    pressed.update!(run_id: 7, status: :succeeded, finished_at: Time.current)
    swapping(Delivery::Github, :workflow_runs, ->(**) { done }) { canned { get console_admin_delivery_path } }
    assert_select "#deployment-request-#{pressed.id}", count: 0
  end

  test "a frozen pipeline leads the console; an expiring token is a notice too; GitHub down is one line" do
    with_deploy_token
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Delivery::Github::EXPIRY_KEY, 3.days.from_now)

    canned(frozen: true) { get console_admin_delivery_path }
    assert_select ".notice--action", text: /Automatic deploys are frozen \(alex · 2026-10-13 · guests this weekend\)/
    assert_select ".notice--action", text: /token expires in 3 days/

    Rails.cache.clear
    swapping(Delivery::Github, :perform, ->(_request) { raise Delivery::Github::Error, "GitHub isn't answering (OpenTimeout)" }) { get console_admin_delivery_path }
    assert_select ".deployment__error[role=alert]", text: /isn't answering/
    assert_select "[data-controller=frame-poll][data-frame-poll-active-value=false]"
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end

  test "the metrics frame shows DORA's four keys as tiles, or why it couldn't" do
    with_deploy_token
    # The canned deployments end on 13 October 2026 and the tiles count the
    # last 30 days, so the frame is read the day after: on the real clock
    # every one of them would fall out of the window in November.
    travel_to Time.utc(2026, 10, 14, 12)

    canned { get metrics_admin_delivery_path }
    assert_select "turbo-frame##{Views::Admin::Deliveries::Metrics::FRAME_ID} .stat-tile", 4
    assert_select ".stat-tile[aria-label=Deploys] .stat-tile__value", text: "4"
    assert_select ".stat-tile[aria-label='Failed changes'] .stat-tile__value", text: "25%"

    swapping(Delivery::Github, :perform, ->(_request) { raise Delivery::Github::Error, "GitHub answered 403" }) { get metrics_admin_delivery_path }
    assert_select ".deployment__error[role=alert]", text: /403/
  end

  test "on dev, GitHub is stood in for: the console works without a token and says so, and this copy is the dev card" do
    ENV["KAMAL_DESTINATION"] = "dev"
    ENV["DEPLOY_GITHUB_CANNED"] = "1"

    get admin_deployment_path
    assert_select "turbo-frame##{Views::Admin::Deliveries::Console::FRAME_ID}"
    assert_select ".deployment__facts", text: /Environment\s*Dev/

    get console_admin_delivery_path
    assert_response :success
    assert_select ".notice--neutral", text: /stood in for/
    assert_select "#deployment-dev .report-tag", text: "This copy"
    assert_select "#deployment-dev .status-badge--good", text: /Answering/
    assert_select "#deployment-dev", text: /try-the-console/
  end

  test "the dev card without a pull request, or with CI still running on it, offers no merge" do
    with_deploy_token

    swapping(Delivery::Github, :pull_request, ->(_branch) { nil }) { canned { get console_admin_delivery_path } }
    assert_select "#deployment-dev" do
      assert_select ".deployment__facts", text: /None open: CI runs on a pull request/
      assert_select ".item-action[href=?]", new_admin_delivery_request_path(kind: :merge), count: 0
      assert_select ".item-menu__entry[href='https://github.com/example/household/compare/main...fix-the-bell?expand=1']", text: /Open a pull request/
    end

    running = Delivery::Github::Run.new(id: 9, number: 9, title: "x", event: "pull_request", status: "in_progress", conclusion: nil, actor: "a", created_at: Time.current,
                                        updated_at: Time.current, html_url: "u", head_sha: GithubFixtures::BRANCH_HEAD, head_branch: GithubFixtures::BRANCH, workflow: "ci.yml")
    runs = Delivery::Github.method(:workflow_runs)
    swapping(Delivery::Github, :workflow_runs, ->(**options) { options[:branch] == GithubFixtures::BRANCH ? [ running ] : runs.call(**options) }) do
      canned { get console_admin_delivery_path }
    end
    assert_select "#deployment-dev .status-badge--warning", text: /CI running on its head/
    assert_select "#deployment-dev .item-action[href=?]", new_admin_delivery_request_path(kind: :merge), count: 0
  end

  test "members have none of this" do
    with_deploy_token
    sign_in profiles(:bob)

    get console_admin_delivery_path
    assert_response :redirect
    get metrics_admin_delivery_path
    assert_response :redirect
  end
end
