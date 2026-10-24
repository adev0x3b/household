# frozen_string_literal: true

# The eval dashboard's controllers: the admin's, since a run writes
# scenario files beside the app's code and spawns the eval process.
class Assistant::Evals::BaseController < Admin::BaseController
  # What can stop a run from starting; launch_error words each.
  LAUNCH_ERRORS = [ AssistantEval::Launcher::Busy, AssistantEval::Preflight::Unavailable, ArgumentError ].freeze

  private

  def models = AssistantEval::Launcher.models

  def launch_error(error)
    case error
    when AssistantEval::Launcher::Busy then t("assistant.evals.errors.busy")
    when AssistantEval::Preflight::Unavailable then t("assistant.evals.errors.model_unavailable", details: error.message)
    else t("assistant.evals.errors.invalid_run", details: error.message)
    end
  end
end
