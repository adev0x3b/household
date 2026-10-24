# frozen_string_literal: true

# A tool call: running, from the event that started it, or finished, from
# the one that records its result. The poll replaces the first with the
# second under the same id.
class Views::Assistant::Evals::Timeline::ToolCall < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(id: "eval-tool-#{@event["seq"]}", class: "eval-tl eval-tl--tool eval-tl--#{state}") do
      details(class: "eval-tl__tool", open: state == "failed") do
        summary(class: "eval-tl__tool-summary") do
          render Views::Assistant::Evals::Status.tool(state).mark
          code { @event["tool"] }
          span(class: "eval-tl__muted") { running? ? t("assistant.evals.live.running") : t("assistant.evals.live.ms", ms: @event["ms"]) }
          span(class: "eval-tl__error") { @event["error"].to_s.truncate(160) } if state == "failed"
        end
        pre(class: "eval-tl__code") { JSON.pretty_generate(@event["arguments"] || {}) }
        pre(class: "eval-tl__code eval-tl__code--result") { @event["result"].to_s } unless running?
      end
    end
  end

  private

  def running? = @event["type"] == "tool_started"

  def state
    if running? then "running"
    elsif @event["ok"] then "ok"
    else "failed"
    end
  end
end
