# frozen_string_literal: true

# The turn's numbers: its outcome, how long it took, its tokens, and a
# warning when a step came near the model's context limit; then the
# checks' notes, folded away.
class Views::Assistant::Evals::Timeline::TurnFinished < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(class: "eval-tl eval-tl--stats") do
      span(class: "eval-tl__muted") { parts.join(" · ") }
      strong(class: "eval-turn__warning") { " #{t("assistant.evals.result.near_limit")}" } if ::Assistant.near_context_limit?(@event["max_step_input"])
      notes
    end
  end

  private

  def parts
    parts = [ t("assistant.evals.live.outcome", outcome: @event["outcome"] || t("assistant.evals.result.none")),
              t("assistant.evals.result.seconds", seconds: @event["seconds"]),
              t("assistant.evals.live.tokens", input: @event["input_tokens"].to_i, output: @event["output_tokens"].to_i) ]
    parts << t("assistant.evals.result.max_in", tokens: @event["max_step_input"]) if @event["max_step_input"].to_i.positive?
    parts
  end

  def notes
    return if @event["notes"].blank?

    details(class: "eval-tl__notes") do
      summary { t("assistant.evals.live.notes", count: @event["notes"].size) }
      @event["notes"].each { |note| p { note } }
    end
  end
end
