# frozen_string_literal: true

# Eval runs: started here (AssistantEval::Launcher, a separate process),
# read back from their results file while and after they run.
#   index   the Runs tab
#   new     the run modal (how many times, which provider and model)
#   create  starts it; show  its page (or, for a frame poll, its compact card)
#   events  the live tracker's poll; pause / resume / destroy (cancel)
class Assistant::Evals::RunsController < Assistant::Evals::BaseController
  PER_PAGE = 20

  before_action :set_run, only: %i[show events destroy pause resume]

  def index
    render_page Views::Assistant::Evals::Runs::Index.new(runs: AssistantEval::RunFile.paginate(page: params[:page], per_page: PER_PAGE))
  end

  def new
    only = params[:only].presence if AssistantEval::Scenario.all.map(&:name).include?(params[:only])
    render_modal(Views::Assistant::Evals::Modals::Run.new(models: models, tag: params[:tag].presence, only: only), page: assistant_evals_path)
  end

  # Runs the scenario its row asked for (`only`), else the ticked ones;
  # none ticked runs every scenario shown (all, or those with the tag).
  def create
    scenarios = AssistantEval::Scenario.all
    names = scenarios.map(&:name)
    shown = params[:tag].present? ? scenarios.select { |s| s.tags.include?(params[:tag]) } : scenarios
    chosen = if params[:only].present? then [ params[:only] ] & names
    else (Array(params[:scenarios]) & names).presence || (params[:tag].present? ? shown.map(&:name) : [])
    end
    run_id = AssistantEval::Launcher.start!(scenarios: chosen, runs: params[:runs], provider: params[:provider], model: params[:model],
                                            notify: current_profile.id)
    redirect_to assistant_evals_run_path(run_id), status: :see_other
  rescue *LAUNCH_ERRORS => e
    toast_flash(:alert, launch_error(e))
    redirect_to assistant_evals_scenarios_path(tag: params[:tag].presence), status: :see_other
  end

  # A turbo-frame request (a compact card polling) gets just that card.
  def show
    if turbo_frame_request?
      render Views::Assistant::Evals::RunPanel.new(run: @run), layout: false
    else
      render_page Views::Assistant::Evals::Runs::Show.new(run: @run)
    end
  end

  # GET …/runs/:id/events?after=N — the live tracker's poll: what happened
  # since event N, as Turbo Stream appends/replaces, plus a fresh status card.
  # Eval-Events-Next is the next N; Eval-Run-Active says whether to keep polling.
  def events
    events = AssistantEval::RunEvents.for(@run)
    streams = events.updates(params[:after].to_i).map do |action, target, event|
      turbo_stream.public_send(action, target, live_component(target, event, events))
    end
    streams << turbo_stream.replace(Views::Assistant::Evals::RunStatusCard::DOM_ID,
                                    Views::Assistant::Evals::RunStatusCard.new(run: @run, events: events))
    response.set_header("Eval-Events-Next", events.size.to_s)
    response.set_header("Eval-Run-Active", @run.active?.to_s)
    render turbo_stream: streams
  end

  # Cancels a running eval.
  def destroy
    AssistantEval::Launcher.cancel!(@run)
    toast_flash(:success, t("assistant.evals.notices.cancelled"))
    redirect_back_or_to assistant_evals_run_path(@run.id), status: :see_other
  end

  # Freezes the run's process (and the GPU it's calling) without losing it.
  def pause
    AssistantEval::Launcher.pause!(@run)
    toast_flash(:success, t("assistant.evals.notices.paused"))
    redirect_back_or_to assistant_evals_run_path(@run.id), status: :see_other
  end

  def resume
    AssistantEval::Launcher.resume!(@run)
    toast_flash(:success, t("assistant.evals.notices.resumed"))
    redirect_back_or_to assistant_evals_run_path(@run.id), status: :see_other
  end

  private

  def set_run
    @run = AssistantEval::RunFile.find(params[:id]) or raise ActiveRecord::RecordNotFound
  end

  def live_component(target, event, events)
    case target
    when "eval-cases" then Views::Assistant::Evals::LiveCases.new(events: events)
    when /\Aeval-case-(\d+)\z/
      Views::Assistant::Evals::LiveCase.new(kase: events.cases.fetch(Regexp.last_match(1).to_i))
    else Views::Assistant::Evals::Timeline.for(event)
    end
  end
end
