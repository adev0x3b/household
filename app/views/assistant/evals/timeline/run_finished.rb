# frozen_string_literal: true

class Views::Assistant::Evals::Timeline::RunFinished < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(class: "eval-tl eval-tl--end") do
      t("assistant.evals.live.run_finished", passed: @event["passed"], errors: @event["errors"], total: @event["total"])
    end
  end
end
