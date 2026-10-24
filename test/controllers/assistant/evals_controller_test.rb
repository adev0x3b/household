# frozen_string_literal: true

require "test_helper"

class Assistant::EvalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in(profiles(:alice).tap { _1.update!(role: :admin) })
    @scenarios = Pathname(Dir.mktmpdir)
    @runs = Pathname(Dir.mktmpdir)
    FileUtils.cp(Rails.root.join("eval/assistant/scenarios/04_lab_report_alone.yml"), @scenarios)
    AssistantEval::Scenario.dir = @scenarios
    AssistantEval::RunFile.dir = @runs
    @runs.join("20260926-120000-qwen3-8b-household.json").write(JSON.generate(
                                                                  model: "qwen3-8b-household", provider: "ollama", runs: 1, finished: true, total: 1,
                                                                  results: [ { scenario: "04_lab_report_alone", passed: false, failures: [ "lab_results: expected 1, got 0" ], error: nil, seconds: 3.2,
                                                                               turns: [ { said: "Cobalamin: 250", tools: [], reply: "Which date?", seconds: 3.1, max_step_input: 2100 } ] } ]
                                                                ))
  end

  teardown do
    AssistantEval::Scenario.dir = nil
    AssistantEval::RunFile.dir = nil
    FileUtils.remove_entry(@scenarios)
    FileUtils.remove_entry(@runs)
  end

  def scenario_params(name: "10_skip_todays_dose", check: "lab_results")
    { scenario: { name: name, description: "Skipping a dose", today: "2026-09-26", seed: [ "" ],
                  messages: [ "I'm skipping today's injection", "" ], expect: [ { check: check, argument: "0" } ] } }
  end

  test "a member who isn't an admin is turned away from every page" do
    sign_in profiles(:bob)

    get assistant_evals_path
    assert_redirected_to root_path
    get assistant_evals_scenarios_path
    assert_redirected_to root_path
    post assistant_evals_runs_path, params: { scenarios: [ "04_lab_report_alone" ] }
    assert_redirected_to root_path
    assert_equal 1, @runs.children.size
  end

  test "the overview says how the latest run did, what fails most and each model, with Run in the navbar" do
    get assistant_evals_path

    assert_response :success
    assert_select ".tabs-nav__tab.is-current[aria-current=page]", text: /Overview/
    assert_select ".stat-tile", 4
    assert_select ".stat-tile__value", text: "0%"
    assert_select ".eval-attention__name[href=?]", edit_assistant_evals_scenario_path("04_lab_report_alone")
    assert_select ".eval-attention__row .status-badge--critical", text: /0\/1/
    assert_select ".eval-attention__row a.item-action[href=?][data-turbo-stream]", new_assistant_evals_run_path(only: "04_lab_report_alone")
    assert_select "a.eval-model[href=?]", assistant_evals_run_path("20260926-120000-qwen3-8b-household"), text: /qwen3-8b-household/
    assert_select ".eval-runs__row", 1
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?][data-turbo-stream]", new_assistant_evals_run_path
  end

  test "the overview with no run yet says how to start one" do
    FileUtils.rm(@runs.children)

    get assistant_evals_path
    assert_response :success
    assert_select ".empty-state", text: /start a run/
    assert_select ".stat-tile", 0
  end

  test "the scenarios page shows each scenario with its last runs, its actions on its row, and the page's in the navbar" do
    get assistant_evals_scenarios_path

    assert_response :success
    assert_select ".tabs-nav__tab.is-current[aria-current=page]", text: /Scenarios/
    assert_select "a.eval-scenario__title[href=?][title='04_lab_report_alone']", edit_assistant_evals_scenario_path("04_lab_report_alone"), text: /Lab report alone/
    assert_select ".eval-history a.eval-history__mark[href=?] i.status-tone--critical", assistant_evals_run_path("20260926-120000-qwen3-8b-household")
    assert_select "input[type=checkbox][name='scenarios[]'][form=eval-run-form][value='04_lab_report_alone']"
    assert_select ".eval-scenario__actions a.item-action[href=?][data-turbo-stream]", new_assistant_evals_run_path(only: "04_lab_report_alone")
    assert_select ".eval-scenario__actions a.item-action--danger[data-turbo-method=delete][href=?]", assistant_evals_scenario_path("04_lab_report_alone")
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_assistant_evals_scenario_path
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?][data-turbo-stream]", new_assistant_evals_run_path
    assert_select ".evals__btn", 0, "no text buttons left"
  end

  test "the run modal: runs on the settings' provider by default, for the ticked boxes or the one row" do
    get new_assistant_evals_run_path(only: "04_lab_report_alone"), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals]"
    assert_select "form#eval-run-form[action=?]", assistant_evals_runs_path
    assert_select "form#eval-run-form input[type=hidden][name=only][value='04_lab_report_alone']"
    assert_select "select[name=provider] option[value=openai]", text: "OpenAI"

    get new_assistant_evals_run_path(only: "../../etc"), as: :turbo_stream
    assert_select "input[name=only]", 0, "only a known scenario"
  end

  test "the runs tab lists every run, a try marked so" do
    @runs.join("20260927-090000-qwen3-8b-household.json").write(JSON.generate(
                                                                  model: "qwen3-8b-household", provider: "ollama", runs: 1, finished: true, total: 1, draft: "10_skip_todays_dose", results: []
                                                                ))

    get assistant_evals_runs_path
    assert_response :success
    assert_select ".tabs-nav__tab.is-current", text: /Runs/
    assert_select ".eval-runs__row", 2
    assert_select ".eval-runs__row:first-child .report-tag", text: /Try: 10_skip_todays_dose/
    assert_select ".eval-runs__title[href=?]", assistant_evals_run_path("20260926-120000-qwen3-8b-household"), text: "qwen3-8b-household on Ollama"
    assert_select ".eval-runs__row .status-badge--good", text: /Finished/
  end

  test "saving a scenario keeps its tags" do
    post assistant_evals_scenarios_path, params: scenario_params.deep_merge(scenario: { tags: "doses, coverage" })

    assert_equal %w[doses coverage], AssistantEval::Scenario.load(@scenarios.join("10_skip_todays_dose.yml")).tags
    get edit_assistant_evals_scenario_path("10_skip_todays_dose")
    assert_select "input[name='scenario[tags]'][value='doses, coverage']"
    assert_select ".navbar-topbar-controls a[href=?][data-turbo-method=delete][data-turbo-confirm]", assistant_evals_scenario_path("10_skip_todays_dose")
    assert_select ".report-footer button[formaction=?]", try_assistant_evals_scenarios_path
  end

  test "writing a scenario saves its file, and editing can rename it" do
    post assistant_evals_scenarios_path, params: scenario_params
    assert_redirected_to edit_assistant_evals_scenario_path("10_skip_todays_dose")
    saved = AssistantEval::Scenario.load(@scenarios.join("10_skip_todays_dose.yml"))
    assert_equal [ "I'm skipping today's injection" ], saved.messages
    assert_equal [ { "lab_results" => 0 } ], saved.expect

    patch assistant_evals_scenario_path("10_skip_todays_dose"), params: scenario_params(name: "10_skip_a_dose")
    assert_redirected_to edit_assistant_evals_scenario_path("10_skip_a_dose")
    assert_not @scenarios.join("10_skip_todays_dose.yml").exist?

    delete assistant_evals_scenario_path("10_skip_a_dose")
    assert_redirected_to assistant_evals_scenarios_path
    assert_not @scenarios.join("10_skip_a_dose.yml").exist?
  end

  test "an invalid scenario is shown again with what's wrong, and nothing is written" do
    post assistant_evals_scenarios_path, params: scenario_params(check: "lab_count")

    assert_response :unprocessable_content
    assert_select ".notice--critical .eval-errors li", text: /lab_count/
    assert_not @scenarios.join("10_skip_todays_dose.yml").exist?
  end

  test "a chat becomes a scenario — only one of your own chats" do
    chat = assistant_chat(profiles(:alice))
    chat.assistant_messages.create!(role: "user", content: "I took my cobalamin")

    get new_assistant_evals_scenario_path(from_chat: chat.id)
    assert_response :success
    assert_select "textarea[name='scenario[messages][]']", text: "I took my cobalamin"

    theirs = assistant_chat(profiles(:bob))
    get new_assistant_evals_scenario_path(from_chat: theirs.id)
    assert_response :not_found
  end

  test "a tag filters the scenarios, and running with none ticked runs what's shown" do
    FileUtils.cp(Rails.root.join("eval/assistant/scenarios/03_moretti_booking_then_done.yml"), @scenarios)

    get assistant_evals_scenarios_path(tag: "appointments")
    assert_select "a.eval-scenario__title", count: 1, text: /Moretti booking then done/
    assert_select ".eval-history--none", text: "Not run yet"
    assert_select ".eval-tags__tag.is-current", text: "appointments"
    assert_select ".navbar-topbar-controls a[href=?]", new_assistant_evals_run_path(tag: "appointments")

    started = nil
    swapping(AssistantEval::Launcher, :start!, ->(**args) { started = args; "20260926-120000-qwen3-8b-household" }) do
      post assistant_evals_runs_path, params: { tag: "appointments", runs: "1" }
    end
    assert_equal [ "03_moretti_booking_then_done" ], started[:scenarios]
  end

  test "starting a run hands the ticked scenarios to the launcher and opens the run" do
    started = nil
    swapping(AssistantEval::Launcher, :start!, ->(**args) { started = args; "20260926-120000-qwen3-8b-household" }) do
      post assistant_evals_runs_path, params: { scenarios: [ "04_lab_report_alone", "../../etc" ], runs: "2", provider: "ollama", model: "qwen3-8b-household" }
    end

    assert_redirected_to assistant_evals_run_path("20260926-120000-qwen3-8b-household")
    assert_equal [ "04_lab_report_alone" ], started[:scenarios], "only known scenario names get through"
    assert_equal @controller.current_profile.id, started[:notify], "whoever started it hears when it ends"

    swapping(AssistantEval::Launcher, :start!, ->(**args) { started = args; "20260926-120000-qwen3-8b-household" }) do
      post assistant_evals_runs_path, params: { only: "04_lab_report_alone", scenarios: [ "03_moretti_booking_then_done" ], runs: "1" }
    end
    assert_equal [ "04_lab_report_alone" ], started[:scenarios], "a row's run is that scenario alone"
  end

  test "pausing and resuming a run signals its process, and the page reflects it" do
    pid = Process.spawn("sleep", "30", pgroup: true)
    id = "20260929-100000-qwen3-8b-household"
    @runs.join("#{id}.json").write(JSON.generate(model: "qwen3-8b-household", provider: "ollama", runs: 1, finished: false, pid: pid, results: []))

    post pause_assistant_evals_run_path(id)
    assert_redirected_to assistant_evals_run_path(id)
    assert_eventually { AssistantEval::RunFile.find(id).status == :paused }

    follow_redirect!
    assert_select ".report-status .status-badge--neutral", text: /Paused/
    assert_select ".navbar-topbar-controls a[href=?][data-turbo-method=post]", resume_assistant_evals_run_path(id)
    assert_select ".navbar-topbar-controls a[href=?][data-turbo-method=delete][data-turbo-confirm]", assistant_evals_run_path(id)

    post resume_assistant_evals_run_path(id)
    assert_eventually { AssistantEval::RunFile.find(id).status == :running }
  ensure
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  test "cancelling a run stops it and goes back where it was asked" do
    id = "20260926-120000-qwen3-8b-household"
    cancelled = nil
    swapping(AssistantEval::Launcher, :cancel!, ->(run) { cancelled = run.id }) do
      delete assistant_evals_run_path(id), headers: { "Referer" => "http://www.example.com#{assistant_evals_runs_path}" }
    end

    assert_equal id, cancelled
    assert_redirected_to assistant_evals_runs_path
    assert_equal I18n.t("assistant.evals.notices.cancelled"), flash[:success]
  end

  test "a run's page lists every result with its turns; the live panel alone for a frame request" do
    get assistant_evals_run_path("20260926-120000-qwen3-8b-household")
    assert_response :success
    assert_select ".report-status .report-segments__segment--critical", 1
    assert_select "details.disclosure[open] summary", text: /04_lab_report_alone.*Failed/m
    assert_select ".eval-problems li", text: "lab_results: expected 1, got 0"
    assert_select ".eval-turn__reply", text: "Which date?"

    get assistant_evals_run_path("20260926-120000-qwen3-8b-household", compact: 1), headers: { "Turbo-Frame" => "eval-run-20260926-120000-qwen3-8b-household" }
    assert_response :success
    assert_select "turbo-frame#eval-run-20260926-120000-qwen3-8b-household .report-status--compact"
    assert_select ".eval-problems", 0
  end

  test "a run with recorded events shows the live tracker, and its poll returns only what's new" do
    id = "20260926-120000-qwen3-8b-household"
    @runs.join("#{id}.events.jsonl").write([
      { type: "run_started", cases: [ { scenario: "04_lab_report_alone", rep: 1 } ], t: 1 },
      { type: "scenario_started", index: 0, scenario: "04_lab_report_alone", rep: 1, t: 2 },
      { type: "tool_started", seq: 1, turn: "0-1", tool: "record_lab_results", arguments: { values: [] }, t: 3 },
      { type: "tool_call", seq: 1, turn: "0-1", tool: "record_lab_results", arguments: { values: [] }, ok: false, error: "give values", t: 4 }
    ].map(&:to_json).join("\n") + "\n")

    get assistant_evals_run_path(id)
    assert_response :success
    assert_select "#eval-live-status.report-status[data-eval-live-target=status]"
    assert_select "#eval-cases #eval-case-0" do |kase|
      assert_match "04_lab_report_alone #1", kase.text.delete("\u200B"), "breakable only at its underscores"
    end
    assert_select "#eval-timeline #eval-tool-1.eval-tl--failed", text: /give values/

    get events_assistant_evals_run_path(id, after: 3), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "4", response.headers["Eval-Events-Next"]
    assert_equal "false", response.headers["Eval-Run-Active"], "the fixture run is finished"
    assert_select "turbo-stream[action=replace][target=eval-tool-1]"
    assert_select "turbo-stream[action=replace][target=eval-live-status]"
    assert_select "turbo-stream[action=append][target=eval-timeline]", 0, "nothing else is new"
  end

  test "trying a scenario runs it once without saving it" do
    tried = nil
    swapping(AssistantEval::Launcher, :start!, ->(**args) { tried = args; "20260926-120000-qwen3-8b-household" }) do
      post try_assistant_evals_scenarios_path, params: scenario_params, as: :turbo_stream
    end

    assert_response :success
    assert_select "turbo-stream[action=update][target=eval-try] template [data-controller=reveal] turbo-frame#eval-run-20260926-120000-qwen3-8b-household"
    assert_equal "10_skip_todays_dose.yml", File.basename(tried[:draft_file])
    assert_not @scenarios.join("10_skip_todays_dose.yml").exist?
  ensure
    FileUtils.rm_rf(File.dirname(tried[:draft_file])) if tried&.dig(:draft_file)
  end

  # The button sits in the sticky footer and the run shows below the form,
  # out of sight on a phone: what stops a Try is said where the reader is.
  test "a Try the model can't take says so in a toast, and nothing shows under the form" do
    unreachable = ->(**) { raise AssistantEval::Preflight::Unavailable, "Failed to open TCP connection" }
    swapping(AssistantEval::Launcher, :start!, unreachable) do
      post try_assistant_evals_scenarios_path, params: scenario_params, as: :turbo_stream
    end

    assert_toast "The run didn't start: Failed to open TCP connection"
    assert_select "turbo-stream[target=eval-try]", 0
  end

  test "a Try of a form that isn't a scenario yet lists its mistakes in toasts and starts nothing" do
    swapping(AssistantEval::Launcher, :start!, ->(**) { flunk "nothing should start" }) do
      post try_assistant_evals_scenarios_path, params: scenario_params(name: "Not a name"), as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_select "turbo-stream[target=toast-container]", minimum: 1
    assert_select "turbo-stream[target=eval-try]", 0
  end
end
