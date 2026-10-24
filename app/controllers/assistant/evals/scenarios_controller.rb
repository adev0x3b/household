# frozen_string_literal: true

# Writing eval scenarios: the files in eval/assistant/scenarios, edited as
# forms (AssistantEval::ScenarioDraft). `try` runs the form's content once,
# without saving it.
class Assistant::Evals::ScenariosController < Assistant::Evals::BaseController
  before_action :set_draft, only: %i[edit update destroy]

  def index
    render_page Views::Assistant::Evals::Scenarios::Index.new(
      scenarios: AssistantEval::Scenario.all, runs: AssistantEval::RunFile.recent(30).reject(&:draft?),
      running: AssistantEval::RunFile.running, tag: params[:tag].presence
    )
  end

  def new
    draft =
      if params[:from_chat].present?
        chat = policy_scope(Assistant::Chat).find(params[:from_chat])
        authorize chat, :show?
        AssistantEval::ScenarioDraft.from_chat(chat)
      else
        AssistantEval::ScenarioDraft.new(name: AssistantEval::Scenario.next_name("new scenario"), today: Date.current.iso8601,
                                         messages: [ "" ])
      end
    render_page form(draft)
  end

  def create
    save(AssistantEval::ScenarioDraft.new.assign(scenario_params))
  end

  def edit
    render_page form(@draft)
  end

  def update
    save(@draft.assign(scenario_params))
  end

  def destroy
    AssistantEval::Scenario.dir.join("#{@draft.original_name}.yml").delete
    toast_flash(:success, t("assistant.evals.notices.deleted", name: @draft.original_name))
    redirect_to assistant_evals_scenarios_path, status: :see_other
  end

  # POST /assistant/evals/scenarios/try — one run of the form as it is now,
  # without saving it. Its run shows under the form and comes into view
  # (TryResult); what stops it — the form's mistakes, a run that can't start
  # (the model unreachable, another run going) — is a toast, seen wherever
  # the reader is, as when the run modal can't start one.
  def try
    draft = AssistantEval::ScenarioDraft.new.assign(scenario_params)
    unless draft.valid?
      return render turbo_stream: draft.errors.full_messages.map { toast(:alert, _1) }, status: :unprocessable_content
    end

    run_id = AssistantEval::Launcher.start!(draft_file: draft.write_temp!, runs: 1, provider: params[:provider], model: params[:model])
    render turbo_stream: turbo_stream.update(Views::Assistant::Evals::Scenarios::Form::TRY_ID, Views::Assistant::Evals::TryResult.new(run: AssistantEval::RunFile.find(run_id)))
  rescue *LAUNCH_ERRORS => e
    refuse(launch_error(e))
  end

  private

  def set_draft
    scenario = AssistantEval::Scenario.find(params[:name]) or raise ActiveRecord::RecordNotFound
    @draft = AssistantEval::ScenarioDraft.from_scenario(scenario)
  end

  def scenario_params
    params.expect(scenario: [ :name, :description, :today, :tags, seed: [], messages: [], expect: [ %i[check argument] ] ])
  end

  def save(draft)
    draft.save!
    toast_flash(:success, t("assistant.evals.notices.saved", name: draft.name))
    redirect_to edit_assistant_evals_scenario_path(draft.name), status: :see_other
  rescue ActiveModel::ValidationError
    render_page form(draft), status: :unprocessable_content
  end

  def form(draft)
    # Checks that already hold with nothing said would pass for a model that does nothing.
    lenient = draft.expect.any? && draft.valid? && AssistantEval::NullBaseline.lenient?(draft.to_scenario)
    Views::Assistant::Evals::Scenarios::Form.new(draft: draft, models: models, lenient: lenient)
  end
end
