# frozen_string_literal: true

require "test_helper"

# A press on the pipeline, from /admin/deployment: each kind opens its
# modal and, pressed with what it needs (a reason, the version typed
# back, the password), becomes a request dispatched to GitHub and
# watched; what's missing comes back as the modal with the reasons;
# without a token nothing starts; members have none of it.
class Admin::DeliveryRequestsControllerTest < ActionDispatch::IntegrationTest
  include CannedPipeline

  isolate_env "APP_VERSION", "DEPLOY_DISPATCH_TOKEN", "KAMAL_DESTINATION"

  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin, password: "a-long-enough-password", password_confirmation: "a-long-enough-password") }
    sign_in @admin
  end

  test "without a token, a press starts nothing and says why" do
    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) { post admin_delivery_requests_path, params: { kind: "deploy", press: { destination: "staging" } }, as: :turbo_stream }

    assert_response :success
    assert_match(/No deploy token/, response.body)
    assert_not Delivery::Request.exists?
  end

  test "the CI modal asks for a branch; the deploy modal says what ships and, for production, asks the password" do
    with_deploy_token

    canned { get new_admin_delivery_request_path(kind: :ci), as: :turbo_stream }
    assert_response :success
    assert_select "turbo-stream[action=update][target=modals]" do
      assert_select "form[action=?]", admin_delivery_requests_path
      assert_select "input[name='press[ref]'][value=main]"
      assert_select "input[name='press[password]']", count: 0
      assert_select "button[type=submit]", text: /Run CI on main/
    end

    canned { get new_admin_delivery_request_path(kind: :deploy, destination: "staging"), as: :turbo_stream }
    assert_select ".modal__title", text: /Deploy a1a1a1a to Staging/
    assert_select "input[name='press[destination]'][value=staging]", visible: false
    assert_select "input[name='press[version]'][value=?]", GithubFixtures::HEAD, visible: false
    assert_select ".report-hint", text: /Nothing new ships/
    assert_select "input[name='press[password]']", count: 0
    assert_select "input[name='press[reason]']:not([required])"

    # The demo takes main's head like staging, with no password asked.
    canned { get new_admin_delivery_request_path(kind: :deploy, destination: "demo"), as: :turbo_stream }
    assert_select ".modal__title", text: /Deploy a1a1a1a to Demo/
    assert_select "input[name='press[destination]'][value=demo]", visible: false
    assert_select "input[name='press[password]']", count: 0

    # A migration that needs the app stopped holds neither: staging rehearses
    # it, the demo goes behind its maintenance page.
    swapping(Delivery::HeldMigrations, :between, ->(*) { [ GithubFixtures::HELD_MIGRATION ] }) do
      canned { get new_admin_delivery_request_path(kind: :deploy, destination: "staging"), as: :turbo_stream }
      assert_select ".notice--action", text: /staging rehearses it on production's data/
      canned { get new_admin_delivery_request_path(kind: :deploy, destination: "demo"), as: :turbo_stream }
      assert_select ".notice--action", text: /the demo deploys behind its maintenance page/
      assert_select "button[type=submit]", text: /Deploy to Demo/
    end

    # Production with a held migration: no deploy, Release instead.
    canned { get new_admin_delivery_request_path(kind: :deploy, destination: "production", version: GithubFixtures::HEAD), as: :turbo_stream }
    assert_select ".modal__title", text: /Deploy a1a1a1a to Production/
    assert_select ".notice--critical", text: /needs the app stopped/
    assert_select ".notice--critical a[href=?]", new_admin_delivery_request_path(kind: :release, version: GithubFixtures::HEAD)
    assert_select "button[type=submit]", count: 0
    assert_select ".deployment-modal__line", text: /same image staging runs/
  end

  test "guessing the password in an action's modal locks the account, which ends the session" do
    with_deploy_token
    @admin.update!(failed_attempts: Devise.maximum_attempts - 2)

    canned { post admin_delivery_requests_path, params: { kind: "restart", press: { destination: "production", password: "a-long-enough-password" } }, as: :turbo_stream }
    assert_equal 0, @admin.reload.failed_attempts, "the right one starts the count again"

    travel(Admin::Sudo::FOR + 1.minute) do # the window closed: the modal asks again
      swapping(Delivery::Github, :dispatch, ->(**) { flunk "nothing reaches production" }) do
        Devise.maximum_attempts.times do
          canned { post admin_delivery_requests_path, params: { kind: "restart", press: { destination: "production", password: "guess" } }, as: :turbo_stream }
        end
      end
      assert_predicate @admin.reload, :access_locked?

      get admin_deployment_path
      assert_redirected_to new_profile_session_path
    end
  end

  test "a production restart asks the password until it was typed lately" do
    with_deploy_token

    canned { get new_admin_delivery_request_path(kind: :restart, destination: "production"), as: :turbo_stream }
    assert_select "input[name='press[password]'][autocomplete=current-password]"
    assert_select ".help", text: /15 minutes/

    canned { post admin_delivery_requests_path, params: { kind: "restart", press: { destination: "production", password: "wrong" } }, as: :turbo_stream }
    assert_response :unprocessable_content
    assert_select "turbo-stream[action=update][target=modals] .notice--critical li", text: /isn't your password/
    assert_not Delivery::Request.exists?

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "restart", press: { destination: "production", password: "a-long-enough-password" } }, as: :turbo_stream }
    end
    assert_response :success
    request = Delivery::Request.sole
    assert_equal({ action: "restart", reason: "alice from the app ##{request.id}", destination: "production" }, sent)
    assert_enqueued_with(job: Delivery::WatchJob, args: [ request.id ])
    assert_select "turbo-stream[action=update][target=modals]"
    assert_select "turbo-stream[action=refresh]:not([request-id])", 1, "the presser's own page shows the press it made"
    assert_match(/restarts in a moment/, response.body)
    assert_match(/Follow it on GitHub/, response.body)

    # Within the window, no password is asked.
    canned { get new_admin_delivery_request_path(kind: :restart, destination: "production"), as: :turbo_stream }
    assert_select "input[name='press[password]']", count: 0
  end

  test "a deploy to staging needs neither password nor reason, and is dispatched with its version" do
    with_deploy_token

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "deploy", press: { destination: "staging", version: GithubFixtures::HEAD, reason: "" } }, as: :turbo_stream }
    end
    assert_response :success
    request = Delivery::Request.sole
    assert_predicate request, :deploy?
    assert_equal [ "staging", GithubFixtures::HEAD, nil ], [ request.destination, request.version, request.reason ]
    assert_equal({ action: "deploy", reason: "alice from the app ##{request.id}", destination: "staging", version: GithubFixtures::HEAD }, sent)
  end

  test "a production deploy of a version that needs the app stopped is refused, whatever the form says" do
    with_deploy_token

    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) do
      canned { post admin_delivery_requests_path, params: { kind: "deploy", press: { destination: "production", version: GithubFixtures::HEAD, password: "a-long-enough-password" } }, as: :turbo_stream }
    end

    assert_response :unprocessable_content
    assert_select ".notice--critical li", text: /needs the app stopped: release it instead/
    assert_not Delivery::Request.exists?
  end

  test "a press of a kind there isn't is a 404" do
    with_deploy_token

    get new_admin_delivery_request_path(kind: "wipe"), as: :turbo_stream
    assert_response :not_found
    post admin_delivery_requests_path, params: { kind: "wipe" }, as: :turbo_stream
    assert_response :not_found
  end

  test "the rollback modal offers earlier versions and wants the sha typed, a reason and the password" do
    with_deploy_token

    canned { get new_admin_delivery_request_path(kind: :rollback), as: :turbo_stream }
    assert_select "form[data-controller=typed-confirm][data-typed-confirm-phrase-value=c3c3c3c]"
    assert_select "input[type=radio][name='press[version]'][value=?][checked][data-phrase=c3c3c3c]", GithubFixtures::OLDER
    assert_select "input[type=radio][name='press[version]'][value=?]", GithubFixtures::OLDEST
    assert_select "input[type=radio][name='press[version]'][value=?]", GithubFixtures::PRODUCTION, count: 0
    assert_select "input[name='press[typed]'][data-typed-confirm-target=input]"
    assert_select "input[name='press[reason]'][required]"
    assert_select "input[name='press[password]']"
    assert_select "button[type=submit][disabled][data-typed-confirm-target=submit].modal__btn--danger", text: /Roll back to c3c3c3c/

    swapping(Delivery::Github, :records, ->(**) { [] }) { canned { get new_admin_delivery_request_path(kind: :rollback), as: :turbo_stream } }
    assert_select ".report-hint", text: /No earlier version was recorded/
    assert_select "input[type=radio][name='press[version]']", count: 0

    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) do
      canned { post admin_delivery_requests_path, params: { kind: "rollback", press: { version: GithubFixtures::OLDER, typed: "c3c3c3", reason: "", password: "nope" } }, as: :turbo_stream }
    end
    assert_response :unprocessable_content
    assert_select ".notice--critical li", 3
    assert_select ".notice--critical li", text: /Say why/
    assert_select ".notice--critical li", text: /Type c3c3c3c/
    assert_select ".notice--critical li", text: /isn't your password/
    assert_select "input[type=radio][value=?][checked]", GithubFixtures::OLDER

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "rollback", press: { version: GithubFixtures::OLDER, typed: " C3C3C3C ", reason: "the bell broke", password: "a-long-enough-password" } }, as: :turbo_stream }
    end
    assert_response :success
    request = Delivery::Request.sole
    assert_equal({ action: "rollback", reason: "alice from the app ##{request.id}: the bell broke", destination: "production", version: GithubFixtures::OLDER }, sent)
  end

  test "the release modal says downtime, the last rehearsal, the held migrations, what ships and that everyone is told" do
    with_deploy_token

    canned { get new_admin_delivery_request_path(kind: :release, version: GithubFixtures::HEAD), as: :turbo_stream }
    assert_select ".modal__title", text: /Release a1a1a1a with downtime/
    assert_select ".notice--action strong", text: "Downtime."
    assert_select ".notice--action", text: /took 77 seconds behind the maintenance page \(the migration itself 12 seconds\)/
    assert_select ".deployment-modal__list .report-mono", text: GithubFixtures::HELD_MIGRATION
    assert_select ".deployment-modal__commits li", 3
    assert_select ".deployment-modal__line", text: /Everyone is told/
    assert_select "form[data-typed-confirm-phrase-value=a1a1a1a]"
    assert_select "button[type=submit][disabled].modal__btn--danger", text: /Release a1a1a1a/

    with_rehearsals([]) { canned { get new_admin_delivery_request_path(kind: :release, version: GithubFixtures::HEAD), as: :turbo_stream } }
    assert_select ".notice--action", text: /Not rehearsed on production's data yet/
    with_rehearsals([ undone_rehearsal ]) { canned { get new_admin_delivery_request_path(kind: :release, version: GithubFixtures::HEAD), as: :turbo_stream } }
    assert_select ".notice--action", text: /was undone: the migration timed out\. It rehearses again first/

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "release", press: { version: GithubFixtures::HEAD, typed: "a1a1a1a", reason: "quiet evening", password: "a-long-enough-password" } }, as: :turbo_stream }
    end
    assert_response :success
    request = Delivery::Request.sole
    assert_predicate request, :release?
    assert_equal({ action: "release", reason: "alice from the app ##{request.id}: quiet evening", destination: "production", version: GithubFixtures::HEAD }, sent)
    assert_match(/rehearses on staging first/, response.body)
  end

  test "freezing sets the variables with a note and is done at once; unfreezing deletes them" do
    with_deploy_token
    set = []
    deleted = []

    canned { get new_admin_delivery_request_path(kind: :freeze), as: :turbo_stream }
    assert_select "input[name='press[reason]'][required]"
    assert_select "input[name='press[password]']"

    swapping(Delivery::Github, :set_variable, ->(name, value) { set << [ name, value ]; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "freeze", press: { reason: "guests this weekend", password: "a-long-enough-password" } }, as: :turbo_stream }
    end
    assert_response :success
    assert_equal [ "DEPLOY_FREEZE", "true" ], set.first
    assert_equal "DEPLOY_FREEZE_NOTE", set.last.first
    assert_match(/alice · .+ · guests this weekend/, set.last.last)
    request = Delivery::Request.sole
    assert_predicate request, :freeze?
    assert_predicate request, :succeeded?
    assert_no_enqueued_jobs only: Delivery::WatchJob

    canned(frozen: true) { get new_admin_delivery_request_path(kind: :unfreeze), as: :turbo_stream }
    assert_select "form[action=?] .deployment-modal__line", admin_delivery_requests_path
    assert_select ".report-hint", text: "alex · 2026-10-13 · guests this weekend"
    assert_select "input[name='press[reason]']:not([required])", 1, "a reason to unfreeze is optional"
    assert_select "input[name='press[password]']", 0, "nor the password typed a moment ago"

    swapping(Delivery::Github, :delete_variable, ->(name) { deleted << name; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "unfreeze", press: { password: "a-long-enough-password" } }, as: :turbo_stream }
    end
    assert_equal %w[DEPLOY_FREEZE DEPLOY_FREEZE_NOTE], deleted
    assert_predicate Delivery::Request.unfreeze.sole, :succeeded?
  end

  test "CI by hand runs on the branch given, main by default" do
    with_deploy_token
    refs = []

    swapping(Delivery::Github, :dispatch_ci, ->(ref:) { refs << ref; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "ci", press: { ref: "" } }, as: :turbo_stream }
      canned { post admin_delivery_requests_path, params: { kind: "ci", press: { ref: "fix-the-bell" } }, as: :turbo_stream }
    end
    assert_equal %w[main fix-the-bell], refs
    assert_equal %w[main fix-the-bell], Delivery::Request.order(:id).pluck(:ref)
    assert_enqueued_jobs 2, only: Delivery::WatchJob
  end

  test "when GitHub refuses, the request is marked failed and the page says what it answered" do
    with_deploy_token

    swapping(Delivery::Github, :dispatch, ->(**) { raise Delivery::Github::Error, "GitHub answered 422: no such workflow" }) do
      canned { post admin_delivery_requests_path, params: { kind: "deploy", press: { destination: "staging" } }, as: :turbo_stream }
    end

    assert_response :success
    assert_match(/GitHub answered 422/, response.body)
    assert_predicate Delivery::Request.sole, :failed?
    assert_equal "GitHub answered 422: no such workflow", Delivery::Request.sole.summary
  end

  test "members have none of this" do
    with_deploy_token
    sign_in profiles(:bob)

    get console_admin_delivery_path
    assert_response :redirect
    get new_admin_delivery_request_path(kind: :release), as: :turbo_stream
    assert_response :forbidden

    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) { post admin_delivery_requests_path, params: { kind: "deploy", press: { destination: "staging" } } }
    assert_not Delivery::Request.exists?
  end

  test "the preview modal prefills the branch dev runs with the others to pick from, keeping its data; fresh by default when nothing runs" do
    with_deploy_token

    canned { get new_admin_delivery_request_path(kind: :preview), as: :turbo_stream }
    assert_response :success
    assert_select "turbo-stream[action=update][target=modals]" do
      assert_select "form[action=?]", admin_delivery_requests_path
      assert_select "[data-controller=preview-form][data-preview-form-current-value=fix-the-bell]"
      assert_select "input[name='press[ref]'][value=fix-the-bell][list=deployment-branches][required][data-preview-form-target=branch]"
      assert_select "datalist#deployment-branches option", 3
      assert_select "datalist#deployment-branches option[value=upcoming-pagination]"
      assert_select "input[type=checkbox][name='press[fresh]'][data-preview-form-target=fresh]:not([checked])"
      assert_select ".deployment-modal__line", text: /Dev runs fix-the-bell at e7e7e7e/
      assert_select "input[name='press[password]']", count: 0
      assert_select "input[name='press[reason]']:not([required])"
      assert_select "button[type=submit]", text: /Preview on Dev/
    end

    swapping(Delivery::Github, :records, ->(**) { [] }) { canned { get new_admin_delivery_request_path(kind: :preview), as: :turbo_stream } }
    assert_select "[data-controller=preview-form][data-preview-form-current-value='']"
    assert_select "input[type=checkbox][name='press[fresh]'][checked]"
    assert_select ".deployment-modal__line", text: /Nothing runs on Dev yet/
  end

  test "a preview needs a branch, and is dispatched to dev with it and whether to start fresh" do
    with_deploy_token

    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) do
      canned { post admin_delivery_requests_path, params: { kind: "preview", press: { ref: " ", fresh: "1" } }, as: :turbo_stream }
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[action=update][target=modals] .notice--critical li", text: /Name the branch/
    assert_select "input[type=checkbox][name='press[fresh]'][checked]"
    assert_not Delivery::Request.exists?

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "preview", press: { ref: " fix-the-bell ", fresh: "1", reason: "the bell" } }, as: :turbo_stream }
    end
    assert_response :success
    request = Delivery::Request.sole
    assert_predicate request, :preview?
    assert_equal [ "dev", "fix-the-bell", true, "the bell" ], [ request.destination, request.ref, request.fresh, request.reason ]
    assert_equal({ action: "preview", reason: "alice from the app ##{request.id}: the bell", destination: "dev", branch: "fix-the-bell", fresh: true }, sent)
    assert_enqueued_with(job: Delivery::WatchJob, args: [ request.id ])
    assert_match(/preview of fix-the-bell on Dev starts in a moment/, response.body)

    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "preview", press: { ref: "fix-the-bell", fresh: "0" } }, as: :turbo_stream }
    end
    assert_equal false, sent[:fresh]
    assert_not Delivery::Request.last.fresh

    canned { get console_admin_delivery_path }
    assert_select ".deployment__run--request .deployment__run-title", text: /preview fix-the-bell on Dev · the bell/
  end

  test "dev takes a restart, never a deploy: main's versions go to staging and production" do
    with_deploy_token

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "restart", press: { destination: "dev" } }, as: :turbo_stream }
    end
    assert_response :success
    assert_equal "dev", sent[:destination]
    assert_equal "dev", Delivery::Request.sole.destination

    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) do
      canned { post admin_delivery_requests_path, params: { kind: "deploy", press: { destination: "dev", version: GithubFixtures::HEAD } }, as: :turbo_stream }
    end
    assert_response :unprocessable_content
    assert_select ".notice--critical li", text: /Pick where/
    assert_equal 1, Delivery::Request.count

    # On dev itself, a deploy with no destination given has nowhere to go either.
    ENV["KAMAL_DESTINATION"] = "dev"
    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) do
      canned { post admin_delivery_requests_path, params: { kind: "deploy", press: { version: GithubFixtures::HEAD } }, as: :turbo_stream }
    end
    assert_response :unprocessable_content
  end

  test "dev stops by hand, keeping what it ran; stopped, it offers a preview, and nothing to restart or stop" do
    with_deploy_token

    canned { get console_admin_delivery_path }
    assert_select "#deployment-dev .item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :stop), text: /Stop/
    canned { get new_admin_delivery_request_path(kind: :stop), as: :turbo_stream }
    assert_select ".deployment-modal__line", text: "Dev runs fix-the-bell at #{GithubFixtures::DEV.first(7)}."
    assert_select "button[type=submit]", text: /Stop Dev/

    sent = nil
    swapping(Delivery::Github, :dispatch, ->(**options) { sent = options; true }) do
      canned { post admin_delivery_requests_path, params: { kind: "stop", press: { reason: "nothing to preview" } }, as: :turbo_stream }
    end
    assert_response :success
    request = Delivery::Request.sole
    assert_predicate request, :stop?
    assert_equal({ action: "stop", reason: "alice from the app ##{request.id}: nothing to preview", destination: "dev" }, sent)
    assert_match(/Dev stops in a moment/, response.body)

    stop = Delivery::Github::Record.new(id: 2, sha: GithubFixtures::DEV, ref: GithubFixtures::DEV, task: "stop", environment: "dev", payload: { "requested_by" => "alice from the app #1" },
                                        created_at: 2.hours.ago, state: "success", description: "stopped", log_url: nil, finished_at: 2.hours.ago, inactive: false)
    records = Delivery::Github.method(:records)
    stopped = ->(&block) { swapping(Delivery::Github, :records, ->(**options) { options[:environment] == "dev" ? [ stop, *records.call(**options) ] : records.call(**options) }, &block) }

    stopped.call { canned { get console_admin_delivery_path } }
    assert_select "#deployment-dev" do
      assert_select ".report-status__time", text: /Stopped about 2 hours ago/
      assert_select ".deployment__facts", text: /Stopped\s*about 2 hours ago by alice from the app #1/
      assert_select ".deployment__facts", text: /Branch\s*fix-the-bell/
      assert_select ".item-action[href=?]", new_admin_delivery_request_path(kind: :preview)
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :restart, destination: "dev"), count: 0
      assert_select ".item-menu__entry[href=?]", new_admin_delivery_request_path(kind: :stop), count: 0
    end

    stopped.call { canned { get new_admin_delivery_request_path(kind: :stop), as: :turbo_stream } }
    assert_select ".report-hint", text: /Dev isn't running: a preview starts it/
    assert_select "button[type=submit]", count: 0
    swapping(Delivery::Github, :dispatch, ->(**) { flunk "dispatched" }) do
      stopped.call { canned { post admin_delivery_requests_path, params: { kind: "stop" }, as: :turbo_stream } }
    end
    assert_response :unprocessable_content
    assert_select ".notice--critical li", text: /Dev isn't running: there is nothing to stop/
    assert_equal 1, Delivery::Request.count
  end

  test "the merge modal names the pull request, warns that dev ran an older head, lists what merges, and needs no password" do
    with_deploy_token

    canned { get new_admin_delivery_request_path(kind: :merge), as: :turbo_stream }
    assert_response :success
    assert_select "turbo-stream[action=update][target=modals]" do
      assert_select ".modal__title", text: "Merge fix-the-bell into main"
      assert_select "form[action=?]", admin_delivery_requests_path
      assert_select ".deployment-modal__line a[href='https://github.com/example/household/pull/46']", text: "#46"
      assert_select ".deployment-modal__line", text: /Ring the bell once per message, by example from fix-the-bell/
      assert_select ".status-badge--good", text: /Ready to merge/
      assert_select ".notice--action", text: /Dev runs e7e7e7e, but the branch's head is f8f8f8f: 1 commit/
      assert_select ".notice--action a[href=?][data-turbo-stream]", new_admin_delivery_request_path(kind: :preview)
      assert_select ".deployment-modal__commits li", text: /Debounce the bell/
      assert_select ".deployment-modal__line", text: /staging takes it on its own/
      assert_select "input[name='press[password]']", count: 0
      assert_select "input[name='press[reason]']:not([required])"
      assert_select "button[type=submit].modal__btn--primary:not([disabled])", text: /Merge #46 into main/
    end

    swapping(Delivery::Github, :pull_request, ->(_branch) { nil }) { canned { get new_admin_delivery_request_path(kind: :merge), as: :turbo_stream } }
    assert_select ".report-hint", text: /fix-the-bell has no open pull request/
    assert_select "button[type=submit]", count: 0
  end

  test "a merge goes through the pull request at the head shown, records the merge commit and follows CI on main" do
    with_deploy_token

    merged = nil
    swapping(Delivery::Github, :merge_pull_request, ->(number, head_sha:, branch:) { merged = [ number, head_sha, branch ]; GithubFixtures::HEAD }) do
      canned { post admin_delivery_requests_path, params: { kind: "merge", press: { reason: "tested on dev" } }, as: :turbo_stream }
    end
    assert_response :success
    assert_equal [ 46, GithubFixtures::BRANCH_HEAD, "fix-the-bell" ], merged
    request = Delivery::Request.sole
    assert_predicate request, :merge_branch?
    assert_equal [ "fix-the-bell", GithubFixtures::HEAD, nil, "tested on dev" ], [ request.ref, request.version, request.destination, request.reason ]
    assert_enqueued_with(job: Delivery::WatchJob, args: [ request.id ])
    assert_match(/fix-the-bell is merged into main \(a1a1a1a\)/, response.body)
    assert_match(%r{actions/workflows/ci.yml}, response.body)

    # Through the fixtures themselves: the PUT answers main's head as the merge commit.
    canned { post admin_delivery_requests_path, params: { kind: "merge", press: {} }, as: :turbo_stream }
    assert_equal GithubFixtures::HEAD, Delivery::Request.last.version

    canned { get console_admin_delivery_path }
    assert_select ".deployment__run--request .deployment__run-title", text: /merge fix-the-bell into main · tested on dev/
  end

  test "a merge is refused when the branch isn't ready, and GitHub's refusal is told" do
    with_deploy_token

    swapping(Delivery::Github, :pull_request, ->(_branch) { nil }) do
      swapping(Delivery::Github, :merge_pull_request, ->(*) { flunk "merged" }) do
        canned { post admin_delivery_requests_path, params: { kind: "merge", press: {} }, as: :turbo_stream }
      end
    end
    assert_response :unprocessable_content
    assert_select ".notice--critical li", text: /has no open pull request/
    assert_not Delivery::Request.exists?

    swapping(Delivery::Github, :records, ->(**) { [] }) do
      canned { post admin_delivery_requests_path, params: { kind: "merge", press: {} }, as: :turbo_stream }
    end
    assert_response :unprocessable_content
    assert_select ".notice--critical li", text: /Dev runs no branch/

    swapping(Delivery::Github, :merge_pull_request, ->(*) { raise Delivery::Github::Error, "GitHub answered 409: Head branch was modified" }) do
      canned { post admin_delivery_requests_path, params: { kind: "merge", press: {} }, as: :turbo_stream }
    end
    assert_response :success
    assert_match(/GitHub answered 409/, response.body)
    assert_predicate Delivery::Request.sole, :failed?
  end

  private

  # GitHub's deployments as the fixtures have them, but with these rehearsals.
  def with_rehearsals(rehearsals, &)
    records = Delivery::Github.method(:records)
    swapping(Delivery::Github, :records, ->(**options) { options[:task] == "rehearse" ? rehearsals : records.call(**options) }, &)
  end

  # A rehearsal of main's head that kamal.yml undid, as GitHub would list it.
  def undone_rehearsal
    Delivery::Github::Record.new(id: 311, sha: GithubFixtures::HEAD, ref: GithubFixtures::HEAD, task: "rehearse", environment: "staging",
                                 payload: {}, created_at: 1.hour.ago, state: "failure", description: "undone: the migration timed out",
                                 log_url: nil, finished_at: 50.minutes.ago, inactive: false)
  end
end
