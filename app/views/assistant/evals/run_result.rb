# frozen_string_literal: true

# One scenario run of a run saved before the live tracker: a report section
# whose summary says pass / fail and how long it took; inside, why, and
# every turn (what was said, which tools were called, what the assistant
# answered). Failures start open.
class Views::Assistant::Evals::RunResult < Views::Base
  # key: the section's remembered open state (the run and the result's place).
  def initialize(result:, key:)
    @result = result
    @key = key
    @status = AssistantEval::RunFile.status(result)
  end

  def view_template
    render Components::Disclosure.new(key: @key, title: @result["scenario"], open: @status != "passed", result: -> { summary }) do
      ul(class: "eval-problems") { problems.each { |problem| li { problem } } } if problems.any?
      ol(class: "report-rows eval-turns") { @result.fetch("turns", []).each { |turn| render_turn(turn) } }
    end
  end

  private

  def summary
    render Views::Assistant::Evals::PassBadge.new(status: @status)
    plain t("assistant.evals.result.seconds", seconds: @result["seconds"])
  end

  def problems = [ @result["error"], *@result["failures"] ].compact

  def render_turn(turn)
    li(class: "eval-turn") do
      p(class: "eval-turn__said") { turn["said"] }
      p(class: "eval-turn__meta") do
        code { turn["tools"].presence&.join(", ") || t("assistant.evals.result.no_tools") }
        plain " · #{t("assistant.evals.result.seconds", seconds: turn["seconds"])}"
        max_in = turn["max_step_input"].to_i
        if max_in.positive?
          plain " · #{t("assistant.evals.result.max_in", tokens: max_in)}"
          strong(class: "eval-turn__warning") { " #{t("assistant.evals.result.near_limit")}" } if ::Assistant.near_context_limit?(max_in)
        end
      end
      p(class: "eval-turn__reply") { turn["reply"] } if turn["reply"].present?
    end
  end
end
