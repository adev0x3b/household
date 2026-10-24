# frozen_string_literal: true

# What the user said, or the button they pressed, on the scenario's day.
class Views::Assistant::Evals::Timeline::TurnStarted < Views::Assistant::Evals::Timeline::Entry
  def view_template
    li(class: "eval-tl eval-tl--said") do
      span(class: "eval-tl__who") do
        render Components::Icon.new("fa-user")
        plain " #{t("assistant.evals.live.user")}"
        span(class: "eval-tl__date") { @event["date"] }
      end
      if @event["button"]
        span(class: "eval-tl__button") { t("assistant.evals.live.pressed", button: @event["said"].delete_prefix("!")) }
      else
        p(class: "eval-tl__said") { @event["said"] }
      end
    end
  end
end
