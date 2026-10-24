# frozen_string_literal: true

# Starting a run: how many times each scenario, on which provider and model
# (the assistant's settings by default). Which scenarios: the one its row
# asked for (`only`), else the boxes ticked on the scenarios page — they
# belong to this form (`form="eval-run-form"`) — else every one shown.
class Views::Assistant::Evals::Modals::Run < Views::Base
  def initialize(models:, tag: nil, only: nil)
    @models = models
    @tag = tag
    @only = only
  end

  def view_template
    render Components::Modal.new(size: :medium) do |modal|
      modal.modal_header(title: t("assistant.evals.modal.title"), subtitle: scope, icon: "fa-play")
      modal.modal_form(url: assistant_evals_runs_path, method: :post, id: "eval-run-form", data: { turbo: true }) do
        input(type: "hidden", name: "tag", value: @tag) if @tag
        input(type: "hidden", name: "only", value: @only) if @only
        modal.modal_body do
          render Components::Field.new(label: t("assistant.evals.runs"), control_id: "eval-run-runs",
                                       help: t("assistant.evals.modal.runs_help", max: AssistantEval::Launcher::MAX_RUNS)) do
            input(type: "number", id: "eval-run-runs", name: "runs", value: 3, min: 1, max: AssistantEval::Launcher::MAX_RUNS, class: "input")
          end
          render Views::Assistant::Evals::ModelFields.new(models: @models)
        end
        modal.modal_footer do
          div(class: "modal__footer-main") do
            button(type: "submit", class: "modal__btn modal__btn--primary") { t("assistant.evals.modal.submit") }
          end
        end
      end
    end
  end

  private

  def scope
    if @only then t("assistant.evals.modal.one", name: @only)
    elsif @tag then t("assistant.evals.modal.tagged", tag: @tag)
    else t("assistant.evals.modal.all")
    end
  end
end
