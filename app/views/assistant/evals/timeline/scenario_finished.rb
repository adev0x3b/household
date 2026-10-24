# frozen_string_literal: true

# How the scenario ended: its badge, its time, and what went wrong.
class Views::Assistant::Evals::Timeline::ScenarioFinished < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(class: "eval-tl eval-tl--result") do
      render Views::Assistant::Evals::PassBadge.new(status: @event["status"])
      span(class: "eval-tl__muted") { t("assistant.evals.result.seconds", seconds: @event["seconds"]) }
      problems = [ @event["error"], *@event["failures"] ].compact
      ul(class: "eval-problems") { problems.each { |problem| li { problem } } } if problems.any?
    end
  end
end
