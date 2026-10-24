# frozen_string_literal: true

class Views::Assistant::Evals::Timeline::ScenarioStarted < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(id: "eval-scenario-#{@event["index"]}", class: "eval-tl eval-tl--scenario") do
      h3(class: "eval-tl__scenario") do
        span(class: "eval-tl__index") { (@event["index"].to_i + 1).to_s }
        plain t("assistant.evals.live.case_label", scenario: @event["scenario"], rep: @event["rep"])
      end
      p(class: "eval-tl__muted") { @event["description"] } if @event["description"].present?
    end
  end
end
